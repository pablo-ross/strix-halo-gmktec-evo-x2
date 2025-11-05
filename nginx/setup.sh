#!/bin/bash

# ==============================================================================
# LLM API Gateway Setup Script
# ==============================================================================
# This script installs nginx with Lua support and configures dynamic model routing
# Usage: ./setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
NGINX_SITE_NAME="llama-api"
NGINX_SITE_PATH="/etc/nginx/sites-available/$NGINX_SITE_NAME"
NGINX_ENABLED_PATH="/etc/nginx/sites-enabled/$NGINX_SITE_NAME"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root for apt operations
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script needs sudo privileges for package installation"
        log_info "Please run: sudo ./setup.sh"
        exit 1
    fi
}

# Check and install required packages
install_packages() {
    log_info "Checking required packages..."

    local packages_to_install=()

    # Check nginx-extras
    if ! dpkg -l | grep -q "^ii.*nginx-extras"; then
        log_warn "nginx-extras not installed"
        packages_to_install+=("nginx-extras")
    else
        log_info "nginx-extras already installed ✓"
    fi

    # Check libnginx-mod-http-lua (Lua module for nginx)
    if ! dpkg -l | grep -q "^ii.*libnginx-mod-http-lua"; then
        log_warn "libnginx-mod-http-lua not installed"
        packages_to_install+=("libnginx-mod-http-lua")
    else
        log_info "libnginx-mod-http-lua already installed ✓"
    fi

    # Check lua-cjson (JSON parsing for Lua)
    if ! dpkg -l | grep -q "^ii.*lua-cjson"; then
        log_warn "lua-cjson not installed"
        packages_to_install+=("lua-cjson")
    else
        log_info "lua-cjson already installed ✓"
    fi

    # Install missing packages
    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log_info "Installing packages: ${packages_to_install[*]}"
        apt update
        apt install -y "${packages_to_install[@]}"
        log_info "Packages installed successfully ✓"
    else
        log_info "All required packages are already installed ✓"
    fi
}

# Load environment file
load_env() {
    if [ ! -f "$ENV_FILE" ]; then
        log_error ".env file not found at: $ENV_FILE"
        log_info "Copy .env.example to .env and customize it:"
        log_info "  cp $SCRIPT_DIR/.env.example $ENV_FILE"
        exit 1
    fi

    log_info "Loading configuration from .env..."

    # Source the env file
    set -a
    source "$ENV_FILE"
    set +a

    # Validate required variables
    if [ -z "$NGINX_HOST" ] || [ -z "$NGINX_PORT" ]; then
        log_error "NGINX_HOST and NGINX_PORT must be set in .env"
        exit 1
    fi

    log_info "Configuration loaded ✓"
}

# Generate Lua routing logic
generate_lua_routing() {
    local lua_code=""

    # Extract all MODEL_* variables
    local models=($(compgen -v | grep "^MODEL_[0-9]"))

    if [ ${#models[@]} -eq 0 ]; then
        log_error "No models defined in .env (MODEL_1, MODEL_2, etc.)"
        exit 1
    fi

    # Log to stderr to avoid polluting nginx config
    log_info "Found ${#models[@]} model(s) in configuration" >&2

    # Generate if-else chain
    local first=true
    for model_var in "${models[@]}"; do
        local model_def="${!model_var}"
        IFS=':' read -r name port patterns <<< "$model_def"

        # Log to stderr to avoid polluting nginx config
        log_info "  - $name (port $port, patterns: $patterns)" >&2

        # Split patterns by comma
        IFS=',' read -ra pattern_array <<< "$patterns"

        # Build Lua conditions
        local conditions=""
        for pattern in "${pattern_array[@]}"; do
            pattern=$(echo "$pattern" | xargs) # trim whitespace
            if [ -n "$conditions" ]; then
                conditions="$conditions or "
            fi
            conditions="${conditions}string.find(model_lower, \"${pattern}\")"
        done

        if [ "$first" = true ]; then
            lua_code="${lua_code}                    if $conditions then\n"
            first=false
        else
            lua_code="${lua_code}                    elseif $conditions then\n"
        fi
        lua_code="${lua_code}                        ngx.var.backend = \"backend_${port}\"\n"
    done

    # Add default case
    local default_port=""
    for model_var in "${models[@]}"; do
        local model_def="${!model_var}"
        IFS=':' read -r name port patterns <<< "$model_def"
        if [ "$name" = "$DEFAULT_MODEL" ]; then
            default_port="$port"
            break
        fi
    done

    if [ -z "$default_port" ]; then
        # Use first model as default
        local first_model="${!models[0]}"
        IFS=':' read -r name default_port patterns <<< "$first_model"
        log_warn "DEFAULT_MODEL not found, using $name (port $default_port) as default"
    fi

    lua_code="${lua_code}                    else\n"
    lua_code="${lua_code}                        -- Default backend\n"
    lua_code="${lua_code}                        ngx.var.backend = \"backend_${default_port}\"\n"
    lua_code="${lua_code}                    end\n"

    echo -e "$lua_code"
}

# Generate upstream blocks
generate_upstreams() {
    local upstreams=""

    local models=($(compgen -v | grep "^MODEL_[0-9]"))

    for model_var in "${models[@]}"; do
        local model_def="${!model_var}"
        IFS=':' read -r name port patterns <<< "$model_def"

        upstreams="${upstreams}upstream backend_${port} {\n"
        upstreams="${upstreams}    server 127.0.0.1:${port};\n"
        upstreams="${upstreams}    keepalive 32;\n"
        upstreams="${upstreams}}\n\n"
    done

    echo -e "$upstreams"
}

# Generate nginx configuration
generate_nginx_config() {
    log_info "Generating nginx configuration..."

    local upstreams=$(generate_upstreams)
    local lua_routing=$(generate_lua_routing)

    # Determine default backend port
    local default_port=""
    local models=($(compgen -v | grep "^MODEL_[0-9]"))
    for model_var in "${models[@]}"; do
        local model_def="${!model_var}"
        IFS=':' read -r name port patterns <<< "$model_def"
        if [ "$name" = "$DEFAULT_MODEL" ]; then
            default_port="$port"
            break
        fi
    done

    if [ -z "$default_port" ]; then
        # Use first model as default
        local first_model="${!models[0]}"
        IFS=':' read -r name default_port patterns <<< "$first_model"
        log_warn "DEFAULT_MODEL not found, using $name (port $default_port) as default"
    fi

    cat > "$NGINX_SITE_PATH" << EOF
# ==============================================================================
# LLM API Gateway - Dynamic Model Routing
# ==============================================================================
# Generated by setup.sh on $(date)
# DO NOT EDIT MANUALLY - Changes will be overwritten

# Backend upstream definitions
${upstreams}

# Lua shared dictionary for caching
lua_shared_dict upstream_cache 10m;

server {
    listen ${NGINX_PORT};
    server_name ${NGINX_HOST};

    # Increase body size for large prompts
    client_max_body_size ${CLIENT_MAX_BODY_SIZE};

    # Main API endpoint
    location /v1/ {
        # Read request body for model field inspection
        lua_need_request_body on;

        # Route based on model field in JSON request
        access_by_lua_block {
            local cjson = require "cjson"
            local body = ngx.req.get_body_data()

            if body then
                local ok, data = pcall(cjson.decode, body)
                if ok and data.model then
                    local model = data.model
                    local model_lower = string.lower(model)

                    -- Dynamic routing based on model patterns
${lua_routing}
                else
                    -- No model field, use default
                    ngx.var.backend = "backend_${default_port}"
                end
            else
                -- No body (e.g., GET /v1/models), use default
                ngx.var.backend = "backend_${default_port}"
            end
        }

        # Proxy to selected backend
        set \$backend "";
        proxy_pass http://\$backend;

        # Standard proxy headers
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection "";

        # Support streaming responses (SSE)
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding on;

        # Timeouts for long-running generations
        proxy_connect_timeout 60s;
        proxy_send_timeout ${PROXY_TIMEOUT}s;
        proxy_read_timeout ${PROXY_TIMEOUT}s;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "LLM API Gateway OK\n";
        add_header Content-Type text/plain;
    }

    # Nginx status (optional, for monitoring)
    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
EOF

    log_info "Nginx configuration generated ✓"
}

# Enable nginx site
enable_site() {
    log_info "Enabling nginx site..."

    # Remove existing symlink if present
    if [ -L "$NGINX_ENABLED_PATH" ]; then
        rm "$NGINX_ENABLED_PATH"
    fi

    # Create symlink
    ln -s "$NGINX_SITE_PATH" "$NGINX_ENABLED_PATH"

    log_info "Site enabled ✓"
}

# Test nginx configuration
test_nginx() {
    log_info "Testing nginx configuration..."

    if nginx -t 2>&1 | grep -q "test is successful"; then
        log_info "Nginx configuration test passed ✓"
        return 0
    else
        log_error "Nginx configuration test failed"
        nginx -t
        return 1
    fi
}

# Reload nginx
reload_nginx() {
    log_info "Reloading nginx..."

    systemctl reload nginx

    if systemctl is-active --quiet nginx; then
        log_info "Nginx reloaded successfully ✓"
    else
        log_error "Nginx failed to start"
        systemctl status nginx
        exit 1
    fi
}

# Main execution
main() {
    log_info "Starting LLM API Gateway setup..."
    echo

    check_sudo
    install_packages
    echo

    # Drop sudo for file operations
    if [ -n "$SUDO_USER" ]; then
        log_info "Dropping privileges for configuration..."
        sudo -u "$SUDO_USER" bash << 'EOSU'
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            ENV_FILE="$SCRIPT_DIR/.env"

            # Check if .env exists
            if [ ! -f "$ENV_FILE" ]; then
                echo -e "\033[0;31m[ERROR]\033[0m .env file not found"
                echo -e "\033[0;32m[INFO]\033[0m Creating .env from .env.example..."
                cp "$SCRIPT_DIR/.env.example" "$ENV_FILE"
                echo -e "\033[1;33m[WARN]\033[0m Please edit .env and run this script again"
                exit 1
            fi
EOSU
        [ $? -eq 1 ] && exit 1
    fi

    load_env
    echo

    generate_nginx_config
    enable_site
    echo

    if ! test_nginx; then
        exit 1
    fi
    echo

    reload_nginx
    echo

    log_info "========================================"
    log_info "Setup completed successfully! ✓"
    log_info "========================================"
    echo
    log_info "API Gateway URL: http://${NGINX_HOST}:${NGINX_PORT}/v1/"
    log_info "Health check: http://${NGINX_HOST}:${NGINX_PORT}/health"
    echo
    log_info "Test the setup with: ./test.sh"
}

main "$@"
