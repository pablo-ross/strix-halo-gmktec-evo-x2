#!/bin/bash

# ==============================================================================
# LLM API Gateway Test Script
# ==============================================================================
# Tests the nginx configuration and model routing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Load environment
if [ ! -f "$ENV_FILE" ]; then
    log_error ".env file not found. Run ./setup.sh first"
    exit 1
fi

source "$ENV_FILE"

BASE_URL="http://${NGINX_HOST}:${NGINX_PORT}"

echo "========================================"
echo "LLM API Gateway Test Suite"
echo "========================================"
echo

# Test 1: Health check
log_test "1. Testing health endpoint..."
if response=$(curl -s -f "${BASE_URL}/health"); then
    log_info "✓ Health check passed: $response"
else
    log_error "✗ Health check failed"
    exit 1
fi
echo

# Test 2: Get models list
log_test "2. Testing /v1/models endpoint (default backend)..."
if response=$(curl -s -f "${BASE_URL}/v1/models" 2>&1); then
    if echo "$response" | grep -q '"object":"list"'; then
        log_info "✓ Models endpoint working"
        echo "$response" | grep -o '"id":"[^"]*"' | head -3
    else
        log_error "✗ Unexpected response format"
        echo "$response"
    fi
else
    log_error "✗ Models endpoint failed"
    echo "$response"
fi
echo

# Test 3: Test each model routing
log_test "3. Testing model-specific routing..."

# Extract all MODEL_* variables
models=($(compgen -v | grep "^MODEL_[0-9]"))

for model_var in "${models[@]}"; do
    model_def="${!model_var}"
    IFS=':' read -r name port patterns <<< "$model_def"

    # Get actual model name from backend
    actual_model=$(curl -s "http://127.0.0.1:${port}/v1/models" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$actual_model" ]; then
        log_error "✗ Backend on port $port not responding"
        continue
    fi

    log_test "Testing routing to $name (port $port)..."

    # Test with actual model name
    response=$(curl -s -X POST "${BASE_URL}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"${actual_model}\",
            \"messages\": [{\"role\": \"user\", \"content\": \"test\"}],
            \"max_tokens\": 1
        }" 2>&1)

    # Check if response is valid (should have choices or error from llama.cpp, not nginx error)
    if echo "$response" | grep -qE '"choices"|"error"|"message"'; then
        log_info "✓ Routing to $name working (model: $actual_model)"
    else
        log_error "✗ Routing to $name failed"
        echo "Response: $response"
    fi

    # Test with pattern matching
    IFS=',' read -ra pattern_array <<< "$patterns"
    first_pattern="${pattern_array[0]}"
    first_pattern=$(echo "$first_pattern" | xargs)

    response=$(curl -s -X POST "${BASE_URL}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"test-${first_pattern}-model\",
            \"messages\": [{\"role\": \"user\", \"content\": \"test\"}],
            \"max_tokens\": 1
        }" 2>&1)

    if echo "$response" | grep -qE '"choices"|"error"|"message"'; then
        log_info "✓ Pattern matching working (pattern: $first_pattern)"
    else
        log_error "✗ Pattern matching failed for $first_pattern"
    fi

    echo
done

# Test 4: Check nginx status
log_test "4. Checking nginx status..."
if systemctl is-active --quiet nginx; then
    log_info "✓ Nginx is running"
else
    log_error "✗ Nginx is not running"
    exit 1
fi
echo

# Test 5: Performance check
log_test "5. Performance check (response time)..."
start_time=$(date +%s%N)
curl -s -o /dev/null "${BASE_URL}/v1/models"
end_time=$(date +%s%N)
elapsed=$((($end_time - $start_time) / 1000000))
log_info "Response time: ${elapsed}ms"

if [ $elapsed -lt 100 ]; then
    log_info "✓ Performance good (< 100ms)"
elif [ $elapsed -lt 500 ]; then
    log_info "✓ Performance acceptable (< 500ms)"
else
    log_error "✗ Performance slow (> 500ms)"
fi
echo

# Summary
echo "========================================"
echo "Test Summary"
echo "========================================"
log_info "API Gateway: ${BASE_URL}"
log_info "Models configured: ${#models[@]}"
echo
log_info "All tests completed!"
echo
echo "Example usage:"
echo "  curl ${BASE_URL}/v1/models"
echo
echo "  curl -X POST ${BASE_URL}/v1/chat/completions \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{"
echo "      \"model\": \"Qwen3-Coder-Next\","
echo "      \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}]"
echo "    }'"
