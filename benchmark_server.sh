#!/bin/bash
# Server benchmark script for llama-server
# Measures prompt processing and text generation performance

SERVER_URL="http://localhost:8080/v1/completions"
RESULTS_FILE="/tmp/benchmark_results.jsonl"
rm -f "$RESULTS_FILE"

echo "Starting benchmark tests..."
echo "=========================================="

# Test configurations: (tokens, description, prompt)
tests=(
  # Small prompt (~30 tokens)
  "30:short:Write a Python function to calculate fibonacci numbers."

  # Medium prompt (~128 tokens)
  "128:medium:Write a comprehensive Python function to implement a binary search tree. The function should include methods for insertion, deletion, searching, and tree traversal. Include proper error handling, type hints, and docstrings. Make sure the implementation is efficient and follows best practices."

  # Large prompt (~256 tokens)
  "256:large:Write a complete Python class for a web scraper that can handle multiple websites concurrently. The implementation should include: 1) Robust error handling for network failures and timeouts, 2) Rate limiting to avoid overwhelming servers, 3) Support for both synchronous and asynchronous operations using asyncio, 4) Proper HTML parsing with BeautifulSoup, 5) Cookie and session management, 6) User-agent rotation, 7) Retry logic with exponential backoff, 8) Logging for debugging purposes, 9) Type hints throughout the code, 10) Comprehensive docstrings explaining the usage. Make the code production-ready and well-structured with separate methods for each concern."

  # Very large prompt (~512 tokens)
  "512:xlarge:Design and implement a comprehensive distributed task queue system in Python similar to Celery. The system should include: 1) A broker abstraction that supports multiple backends (Redis, RabbitMQ, and in-memory for testing), 2) Worker processes that can execute tasks concurrently using multiprocessing or threading, 3) Task serialization and deserialization with support for complex data types, 4) Priority queues for task execution ordering, 5) Task retry logic with configurable retry policies and exponential backoff, 6) Dead letter queues for failed tasks, 7) Task result storage with TTL support, 8) Worker heartbeat monitoring and automatic cleanup of dead workers, 9) Task chaining and workflow composition, 10) Rate limiting per task type, 11) Comprehensive logging and monitoring hooks, 12) Graceful shutdown handling, 13) Support for periodic tasks (cron-like scheduling), 14) Task middleware for cross-cutting concerns like timing and error tracking, 15) Full test coverage including integration tests. Include proper error handling throughout, type hints, detailed docstrings, and configuration management. Structure the code in a modular way with clear separation of concerns. Provide examples of how to use the system for common scenarios."
)

# Run each test configuration 3 times
for test_config in "${tests[@]}"; do
  IFS=':' read -r expected_tokens desc prompt <<< "$test_config"

  echo ""
  echo "Testing: $desc prompt (~$expected_tokens tokens)"
  echo "----------------------------------------"

  for run in 1 2 3; do
    echo -n "  Run $run/3... "

    start=$(date +%s.%N)
    response=$(curl -s "$SERVER_URL" \
      -H "Content-Type: application/json" \
      -d "{
        \"prompt\": \"$prompt\",
        \"max_tokens\": 128,
        \"temperature\": 0.7,
        \"stream\": false
      }")
    end=$(date +%s.%N)

    # Calculate total time
    total_time=$(echo "$end - $start" | bc -l)

    # Extract tokens and timing from response
    prompt_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens // 0')
    completion_tokens=$(echo "$response" | jq -r '.usage.completion_tokens // 0')

    # Extract timings if available
    prompt_ms=$(echo "$response" | jq -r '.timings.prompt_ms // 0')
    predicted_ms=$(echo "$response" | jq -r '.timings.predicted_ms // 0')
    prompt_per_second=$(echo "$response" | jq -r '.timings.prompt_per_second // 0')
    predicted_per_second=$(echo "$response" | jq -r '.timings.predicted_per_second // 0')

    # If timings not in response, calculate from wall time
    if [ "$prompt_per_second" == "0" ] || [ "$prompt_per_second" == "null" ]; then
      prompt_per_second=$(echo "scale=2; $prompt_tokens / $total_time" | bc -l)
    fi

    if [ "$predicted_per_second" == "0" ] || [ "$predicted_per_second" == "null" ]; then
      predicted_per_second=$(echo "scale=2; $completion_tokens / $total_time" | bc -l)
    fi

    echo "{\"test\":\"$desc\",\"run\":$run,\"prompt_tokens\":$prompt_tokens,\"completion_tokens\":$completion_tokens,\"total_time\":$total_time,\"prompt_per_second\":$prompt_per_second,\"predicted_per_second\":$predicted_per_second}" >> "$RESULTS_FILE"

    echo "Done (${total_time}s, prompt: ${prompt_per_second} t/s, gen: ${predicted_per_second} t/s)"

    # Small delay between runs
    sleep 1
  done
done

echo ""
echo "=========================================="
echo "Benchmark complete! Results saved to $RESULTS_FILE"
echo ""
echo "Performance Summary:"
echo "=========================================="

# Calculate averages for each test type
for test_type in short medium large xlarge; do
  avg_prompt=$(jq -s "map(select(.test==\"$test_type\")) | map(.prompt_per_second) | add / length" "$RESULTS_FILE")
  avg_gen=$(jq -s "map(select(.test==\"$test_type\")) | map(.predicted_per_second) | add / length" "$RESULTS_FILE")
  avg_prompt_tokens=$(jq -s "map(select(.test==\"$test_type\")) | map(.prompt_tokens) | add / length | floor" "$RESULTS_FILE")

  if [ "$avg_prompt" != "null" ]; then
    printf "%-10s (%3d tokens): Prompt: %6.2f t/s, Generation: %5.2f t/s\n" "$test_type" "$avg_prompt_tokens" "$avg_prompt" "$avg_gen"
  fi
done

echo "=========================================="
