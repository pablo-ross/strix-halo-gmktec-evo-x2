#!/bin/bash
# ==============================================================================
# Multi-Model LLM Benchmark Suite
# ==============================================================================
# Tests all llama-server instances on AMD Strix Halo system
# Models: Qwen3-Coder-30B, Bielik-11B, Qwen2.5-7B, DeepSeek-R1, Nomic-Embed, E5-Large
#
# LOCALE SUPPORT:
# ---------------
# This script works correctly on both English and Polish (or any other) locales.
#
# The challenge: Different locales use different decimal separators:
#   - English (en_US): 1234.56  (period)
#   - Polish (pl_PL):  1234,56  (comma)
#
# Without proper handling, Polish locales would cause:
#   - bc calculations to fail (bc requires periods)
#   - printf to use commas, breaking numeric comparisons
#   - jq to receive malformed JSON numbers
#
# Our solution:
#   1. Force LC_NUMERIC=C and LC_ALL=C for all operations
#   2. Use calc() wrapper for all bc arithmetic
#   3. Use format_number() wrapper for all printf formatting
#   4. Store all data with periods (JSON standard)
#
# This ensures:
#   ✓ Calculations always work (bc gets periods)
#   ✓ Display always works (printf gets periods)
#   ✓ JSON always valid (jq gets periods)
#   ✓ Works on any system locale
# ==============================================================================

set -euo pipefail

# ==============================================================================
# LOCALE-SAFE NUMERIC OPERATIONS
# ==============================================================================

# Save original locale (for reference, not used in calculations)
ORIGINAL_LC_NUMERIC="${LC_NUMERIC:-}"
ORIGINAL_LANG="${LANG:-}"

# Force C locale for ALL numeric operations (periods as decimal separators)
# This is critical for:
#   - bc arithmetic (requires period)
#   - printf formatting (requires period)
#   - jq parsing (JSON requires period)
export LC_NUMERIC=C
export LC_ALL=C

# Wrapper function for safe floating-point arithmetic
# Ensures bc always uses period as decimal separator
# Usage: calc "10.5 + 3.7"
# Usage: calc "scale=2; 100 / 3"
calc() {
  echo "$@" | LC_NUMERIC=C bc -l
}

# Format number for display with specified decimal places
# Accepts both period and comma input, always outputs period
# Usage: format_number <number> <decimal_places>
# Example: format_number 3.14159 2  -> "3.14"
# Example: format_number "12,34" 2  -> "12.34"
format_number() {
  local number=$1
  local decimals=${2:-2}

  # Normalize: convert comma to period (handles Polish input)
  number=$(echo "$number" | tr ',' '.')

  # Format with printf using C locale (always outputs period)
  LC_NUMERIC=C printf "%.${decimals}f" "$number" 2>/dev/null || echo "$number"
}

# Model configurations: name:port:description:type
declare -A MODELS=(
  ["qwen3"]="Qwen3-Coder-30B:8080:Code generation (30B):completion"
  ["bielik"]="Bielik-11B:8081:Polish language (11B):completion"
  ["qwen25"]="Qwen2.5-Coder-7B:8082:Fast autocomplete (7B):completion"
  ["deepseek"]="DeepSeek-R1-Distill:8084:Reasoning (32B):completion"
  ["nomic"]="Nomic-Embed-v2-MoE:8083:Text embeddings (MoE):embedding"
  ["e5large"]="E5-Large-v2:8085:Embeddings (335M):embedding"
)

RESULTS_DIR="/tmp/llm_benchmarks"
mkdir -p "$RESULTS_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Display banner
show_banner() {
  echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  ${MAGENTA}Multi-Model LLM Benchmark Suite${NC}                        ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BLUE}AMD Ryzen AI Max+ 395 w/ Radeon 8060S (Strix Halo)${NC}     ${CYAN}║${NC}"
  echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

# Display model selection menu
show_menu() {
  echo -e "${YELLOW}Available Models:${NC}"
  echo ""
  echo -e "  ${GREEN}1)${NC} Qwen3-Coder-30B    (port 8080) - Code generation"
  echo -e "  ${GREEN}2)${NC} Bielik-11B         (port 8081) - Polish language"
  echo -e "  ${GREEN}3)${NC} Qwen2.5-Coder-7B   (port 8082) - Fast autocomplete"
  echo -e "  ${GREEN}4)${NC} DeepSeek-R1        (port 8084) - Reasoning"
  echo -e "  ${GREEN}5)${NC} Nomic-Embed-v2     (port 8083) - Text embeddings (MoE)"
  echo -e "  ${GREEN}6)${NC} E5-Large-v2        (port 8085) - Text embeddings (335M)"
  echo -e "  ${GREEN}7)${NC} ${MAGENTA}Test ALL models${NC}"
  echo -e "  ${GREEN}8)${NC} Exit"
  echo ""
  echo -n "Select model to benchmark (1-8): "
}

# Check if server is responsive
check_server() {
  local port=$1
  local name=$2

  echo -n "  Checking $name (port $port)... "

  if curl -s --max-time 2 "http://localhost:$port/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Online${NC}"
    return 0
  else
    echo -e "${RED}✗ Offline${NC}"
    return 1
  fi
}

# Get model-specific test configurations
get_tests_for_model() {
  local model_key=$1

  case $model_key in
    "qwen3")
      # Code generation tests
      cat <<'EOF'
short:Write a Python function to calculate fibonacci numbers efficiently using memoization.
medium:Create a Python class for a binary search tree with insert, delete, search, and traversal methods. Include type hints and docstrings.
large:Implement a distributed task queue system in Python with Redis backend, worker pool management, task retry logic, and result storage. Include comprehensive error handling.
polish_code:Napisz funkcję w Pythonie do sortowania listy liczb algorytmem quicksort. Dodaj komentarze po polsku.
EOF
      ;;
    "bielik")
      # Polish language tests
      cat <<'EOF'
short:Odpowiedz na pytanie: Jakie są główne zalety programowania funkcyjnego?
medium:Napisz krótką opowieść science fiction o podróży w czasie. Historia powinna zawierać paradoks czasowy.
large:Wytłumacz szczegółowo, jak działa protokół HTTP/HTTPS. Omów różnice między GET i POST, mechanizmy uwierzytelniania, oraz bezpieczeństwo połączeń. Odpowiedź powinna być zrozumiała dla początkujących programistów.
english_test:Explain the difference between machine learning and deep learning in simple terms.
EOF
      ;;
    "qwen25")
      # Fast autocomplete tests (shorter prompts)
      cat <<'EOF'
short:Complete this function: def calculate_average(numbers):
medium:Complete this class definition with methods: class DataProcessor:\n    def __init__(self, data):\n        self.data = data
large:Complete this async function: async def fetch_data(url: str, session: aiohttp.ClientSession) -> dict:
polish_code:Uzupełnij tę funkcję: def znajdz_maximum(lista):
EOF
      ;;
    "deepseek")
      # Reasoning and problem-solving tests
      cat <<'EOF'
short:Solve this math problem step by step: If x + 2x = 15, what is the value of x?
medium:A farmer has chickens and rabbits. There are 35 heads and 94 legs total. How many chickens and rabbits are there? Show your reasoning.
large:You have 8 coins that look identical, but one is counterfeit and weighs less. You have a balance scale. What is the minimum number of weighings needed to identify the fake coin? Explain your strategy.
polish_reason:Rozwiąż zagadkę logiczną: Masz trzy pudełka. Jedno zawiera tylko jabłka, drugie tylko pomarańcze, a trzecie jabłka i pomarańcze. Wszystkie pudełka są źle oznakowane. Możesz wyciągnąć jeden owoc z jednego pudełka. Jak określić, co jest w każdym pudełku?
EOF
      ;;
    "nomic")
      # Embedding tests - different text types and lengths
      cat <<'EOF'
short:semantic search
medium:Python function for binary search tree implementation
large:The quick brown fox jumps over the lazy dog. This is a common pangram used for testing text rendering and typography. It contains every letter of the English alphabet at least once. Software developers often use this phrase when testing fonts, keyboards, and other text-related features.
code:def calculate_fibonacci(n: int) -> int:\n    if n <= 1:\n        return n\n    return calculate_fibonacci(n-1) + calculate_fibonacci(n-2)
polish:Szybki brązowy lis przeskakuje przez leniwego psa. To popularne zdanie testowe zawierające wiele polskich znaków diakrytycznych.
technical:Implement a RESTful API endpoint using FastAPI framework with async/await pattern, SQLAlchemy ORM for database operations, Pydantic models for request validation, and JWT authentication middleware.
EOF
      ;;
    "e5large")
      # E5-Large embedding tests - same test suite for comparison
      cat <<'EOF'
short:semantic search
medium:Python function for binary search tree implementation
large:The quick brown fox jumps over the lazy dog. This is a common pangram used for testing text rendering and typography. It contains every letter of the English alphabet at least once. Software developers often use this phrase when testing fonts, keyboards, and other text-related features.
code:def calculate_fibonacci(n: int) -> int:\n    if n <= 1:\n        return n\n    return calculate_fibonacci(n-1) + calculate_fibonacci(n-2)
polish:Szybki brązowy lis przeskakuje przez leniwego psa. To popularne zdanie testowe zawierające wiele polskich znaków diakrytycznych.
technical:Implement a RESTful API endpoint using FastAPI framework with async/await pattern, SQLAlchemy ORM for database operations, Pydantic models for request validation, and JWT authentication middleware.
EOF
      ;;
  esac
}

# Run embedding benchmark for a specific model
benchmark_embedding_model() {
  local model_key=$1
  local model_info="${MODELS[$model_key]}"

  IFS=':' read -r model_name port description model_type <<< "$model_info"

  local results_file="$RESULTS_DIR/${model_key}_$(date +%Y%m%d_%H%M%S).jsonl"

  echo ""
  echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  Testing: ${MAGENTA}$model_name${NC}"
  echo -e "${CYAN}║${NC}  ${BLUE}$description${NC}"
  echo -e "${CYAN}║${NC}  Port: ${YELLOW}$port${NC} ${CYAN}[EMBEDDING MODE]${NC}"
  echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  # Check if server is online
  if ! check_server "$port" "$model_name"; then
    echo -e "${RED}Skipping $model_name - server not responding${NC}"
    return 1
  fi

  echo ""
  echo -e "${YELLOW}Running embedding benchmark tests...${NC}"

  local server_url="http://localhost:$port/v1/embeddings"
  local test_num=0

  # Read test configurations
  while IFS=':' read -r test_type input_text; do
    test_num=$((test_num + 1))

    echo ""
    echo -e "${BLUE}Test $test_num: ${test_type}${NC}"
    echo "----------------------------------------"

    # Run each test 3 times
    for run in 1 2 3; do
      echo -n "  Run $run/3... "

      local start=$(date +%s.%N)
      local response=$(curl -s --max-time 30 "$server_url" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg input "$input_text" '{input: $input}')" 2>/dev/null)
      local end=$(date +%s.%N)

      # Check if request was successful
      if [ -z "$response" ]; then
        echo -e "${RED}Failed (timeout or error)${NC}"
        continue
      fi

      # Calculate total time
      local total_time=$(calc "$end - $start")

      # Extract tokens and embedding dimensions
      local prompt_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens // 0')
      local embedding_dim=$(echo "$response" | jq -r '.data[0].embedding | length // 0')

      # Calculate speed
      local tokens_per_second=$(calc "scale=2; $prompt_tokens / $total_time")

      # Save results
      echo "{\"model\":\"$model_key\",\"test\":\"$test_type\",\"run\":$run,\"prompt_tokens\":$prompt_tokens,\"embedding_dim\":$embedding_dim,\"total_time\":$total_time,\"tokens_per_second\":$tokens_per_second,\"timestamp\":\"$(date -Iseconds)\"}" >> "$results_file"

      # Format for display
      local display_time=$(format_number "$total_time" 3)
      local display_speed=$(format_number "$tokens_per_second" 2)

      echo -e "${GREEN}Done${NC} (${display_time}s, ${prompt_tokens} tokens, ${display_speed} t/s, dim: ${embedding_dim})"

      # Small delay between runs
      sleep 0.5
    done
  done < <(get_tests_for_model "$model_key")

  echo ""
  echo -e "${GREEN}✓ Benchmark complete for $model_name${NC}"
  echo -e "${BLUE}Results saved to: $results_file${NC}"

  # Display summary
  show_embedding_summary "$results_file" "$model_key"
}

# Run benchmark for a specific model
benchmark_model() {
  local model_key=$1
  local model_info="${MODELS[$model_key]}"

  IFS=':' read -r model_name port description model_type <<< "$model_info"

  # Route to appropriate benchmark function based on model type
  if [ "$model_type" = "embedding" ]; then
    benchmark_embedding_model "$model_key"
    return $?
  fi

  local results_file="$RESULTS_DIR/${model_key}_$(date +%Y%m%d_%H%M%S).jsonl"

  echo ""
  echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  Testing: ${MAGENTA}$model_name${NC}"
  echo -e "${CYAN}║${NC}  ${BLUE}$description${NC}"
  echo -e "${CYAN}║${NC}  Port: ${YELLOW}$port${NC}"
  echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  # Check if server is online
  if ! check_server "$port" "$model_name"; then
    echo -e "${RED}Skipping $model_name - server not responding${NC}"
    return 1
  fi

  echo ""
  echo -e "${YELLOW}Running benchmark tests...${NC}"

  local server_url="http://localhost:$port/v1/completions"
  local test_num=0

  # Read test configurations
  while IFS=':' read -r test_type prompt; do
    test_num=$((test_num + 1))

    echo ""
    echo -e "${BLUE}Test $test_num: ${test_type}${NC}"
    echo "----------------------------------------"

    # Run each test 3 times
    for run in 1 2 3; do
      echo -n "  Run $run/3... "

      local start=$(date +%s.%N)
      local response=$(curl -s --max-time 120 "$server_url" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg prompt "$prompt" '{prompt: $prompt, max_tokens: 128, temperature: 0.7, stream: false}')" 2>/dev/null)
      local end=$(date +%s.%N)

      # Check if request was successful
      if [ -z "$response" ]; then
        echo -e "${RED}Failed (timeout or error)${NC}"
        continue
      fi

      # Calculate total time
      local total_time=$(calc "$end - $start")

      # Extract tokens and timing
      local prompt_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens // 0')
      local completion_tokens=$(echo "$response" | jq -r '.usage.completion_tokens // 0')

      # Calculate speeds
      local prompt_per_second=$(calc "scale=2; $prompt_tokens / $total_time")
      local predicted_per_second=$(calc "scale=2; $completion_tokens / $total_time")

      # Save results
      echo "{\"model\":\"$model_key\",\"test\":\"$test_type\",\"run\":$run,\"prompt_tokens\":$prompt_tokens,\"completion_tokens\":$completion_tokens,\"total_time\":$total_time,\"prompt_per_second\":$prompt_per_second,\"predicted_per_second\":$predicted_per_second,\"timestamp\":\"$(date -Iseconds)\"}" >> "$results_file"

      # Format for display
      local display_time=$(format_number "$total_time" 3)
      local display_prompt_speed=$(format_number "$prompt_per_second" 2)
      local display_gen_speed=$(format_number "$predicted_per_second" 2)

      echo -e "${GREEN}Done${NC} (${display_time}s, prompt: ${display_prompt_speed} t/s, gen: ${display_gen_speed} t/s)"

      # Small delay between runs
      sleep 1
    done
  done < <(get_tests_for_model "$model_key")

  echo ""
  echo -e "${GREEN}✓ Benchmark complete for $model_name${NC}"
  echo -e "${BLUE}Results saved to: $results_file${NC}"

  # Display summary
  show_summary "$results_file" "$model_key"
}

# Show benchmark summary
show_summary() {
  local results_file=$1
  local model_key=$2

  echo ""
  echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}Performance Summary:${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"

  # Get unique test types
  local test_types=$(jq -r '.test' "$results_file" | sort -u)

  printf "${BLUE}%-20s %-12s %-15s %-15s${NC}\n" "Test Type" "Avg Tokens" "Prompt (t/s)" "Generation (t/s)"
  echo "───────────────────────────────────────────────────────────"

  while IFS= read -r test_type; do
    local avg_prompt_tokens=$(jq -s "map(select(.test==\"$test_type\")) | map(.prompt_tokens) | add / length | floor" "$results_file")
    local avg_prompt_speed=$(jq -s "map(select(.test==\"$test_type\")) | map(.prompt_per_second) | add / length" "$results_file")
    local avg_gen_speed=$(jq -s "map(select(.test==\"$test_type\")) | map(.predicted_per_second) | add / length" "$results_file")

    # Format numbers for display
    local display_prompt_speed=$(format_number "$avg_prompt_speed" 2)
    local display_gen_speed=$(format_number "$avg_gen_speed" 2)

    printf "%-20s %-12s ${GREEN}%-15s${NC} ${GREEN}%-15s${NC}\n" "$test_type" "$avg_prompt_tokens" "$display_prompt_speed" "$display_gen_speed"
  done <<< "$test_types"

  echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

# Show embedding benchmark summary
show_embedding_summary() {
  local results_file=$1
  local model_key=$2

  echo ""
  echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}Embedding Performance Summary:${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"

  # Get unique test types
  local test_types=$(jq -r '.test' "$results_file" | sort -u)

  printf "${BLUE}%-20s %-12s %-15s %-15s${NC}\n" "Test Type" "Avg Tokens" "Speed (t/s)" "Dimensions"
  echo "───────────────────────────────────────────────────────────"

  while IFS= read -r test_type; do
    local avg_tokens=$(jq -s "map(select(.test==\"$test_type\")) | map(.prompt_tokens) | add / length | floor" "$results_file")
    local avg_speed=$(jq -s "map(select(.test==\"$test_type\")) | map(.tokens_per_second) | add / length" "$results_file")
    local embedding_dim=$(jq -s "map(select(.test==\"$test_type\")) | map(.embedding_dim) | .[0]" "$results_file")

    # Format numbers for display
    local display_speed=$(format_number "$avg_speed" 2)

    printf "%-20s %-12s ${GREEN}%-15s${NC} %-15s\n" "$test_type" "$avg_tokens" "$display_speed" "$embedding_dim"
  done <<< "$test_types"

  echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

# Main program
main() {
  show_banner

  # Parse command line arguments
  if [ $# -gt 0 ]; then
    case $1 in
      qwen3|bielik|qwen25|deepseek|nomic|e5large)
        benchmark_model "$1"
        exit 0
        ;;
      all)
        for model in qwen3 bielik qwen25 deepseek nomic e5large; do
          benchmark_model "$model" || true
          echo ""
        done
        exit 0
        ;;
      --help|-h)
        echo "Usage: $0 [model|all]"
        echo ""
        echo "Text Generation Models: qwen3, bielik, qwen25, deepseek"
        echo "Embedding Models: nomic, e5large"
        echo "Example: $0 qwen3"
        echo "Example: $0 nomic"
        echo "Example: $0 e5large"
        echo "Example: $0 all"
        exit 0
        ;;
      *)
        echo "Unknown model: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
    esac
  fi

  # Interactive menu
  while true; do
    show_menu
    read -r choice

    case $choice in
      1) benchmark_model "qwen3" ;;
      2) benchmark_model "bielik" ;;
      3) benchmark_model "qwen25" ;;
      4) benchmark_model "deepseek" ;;
      5) benchmark_model "nomic" ;;
      6) benchmark_model "e5large" ;;
      7)
        echo ""
        echo -e "${MAGENTA}Running benchmarks for ALL models...${NC}"
        for model in qwen3 bielik qwen25 deepseek nomic e5large; do
          benchmark_model "$model" || true
          echo ""
        done
        ;;
      8)
        echo ""
        echo -e "${GREEN}Exiting...${NC}"
        exit 0
        ;;
      *)
        echo -e "${RED}Invalid choice. Please select 1-8.${NC}"
        ;;
    esac

    echo ""
    echo -n "Press Enter to continue..."
    read -r
    clear
    show_banner
  done
}

main "$@"
