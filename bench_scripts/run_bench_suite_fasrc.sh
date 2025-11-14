#!/bin/bash

# This script runs a suite of benchmarks against a running SGLang server
# to evaluate performance across different prompt lengths and concurrency levels.

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <port>"
    echo "Example: $0 8001"
    exit 1
fi

PORT=$1

# --- Configuration ---
PROMPT_LENGTHS=(32 128 512 1024 2048 4096)
CONCURRENCIES=(1 2 4 8 16 32 64)
OUTPUT_LENGTHS=(1 1000)

# For the prompt length sweep, we fix concurrency.
FIXED_CONCURRENCY_FOR_PROMPT_SWEEP=1

# For the concurrency sweep, we fix the prompt length.
FIXED_PROMPT_LENGTH_FOR_CONCURRENCY_SWEEP=1024

# Number of prompts for each benchmark run.
NUM_PROMPTS=1000

# Path to the python executable in the virtual environment
PYTHON_EXEC="/n/juncheng_lab/Lab/llm-workload/.venv/bin/python3"

# --- Benchmark Execution ---

BASE_LOG_DIR="bench_results"
echo "Starting benchmark suite. Results will be saved in '$BASE_LOG_DIR'."

for output_len in "${OUTPUT_LENGTHS[@]}"; do
    # --- 1. Prompt Length Sweep ---
    LOG_DIR_PROMPT="$BASE_LOG_DIR/output_${output_len}/prompt_sweep"
    mkdir -p "$LOG_DIR_PROMPT"
    echo ""
    echo "--- Running Prompt Length Sweep (Output Length: $output_len, Concurrency: $FIXED_CONCURRENCY_FOR_PROMPT_SWEEP) ---"

    for prompt_len in "${PROMPT_LENGTHS[@]}"; do
        LOG_FILE="$LOG_DIR_PROMPT/prompt-${prompt_len}-concurrency-${FIXED_CONCURRENCY_FOR_PROMPT_SWEEP}.log"

        if [ -f "$LOG_FILE" ]; then
            echo "Skipping: Log file exists at $LOG_FILE"
        else
            echo "Benchmarking: Prompt Length=$prompt_len. Logging to $LOG_FILE"
            "$PYTHON_EXEC" -m sglang.bench_serving \
                --backend sglang \
                --host 127.0.0.1 --port "$PORT" \
                --dataset-name random \
                --random-input-len "$prompt_len" \
                --random-output-len "$output_len" \
                --num-prompts "$NUM_PROMPTS" \
                --max-concurrency "$FIXED_CONCURRENCY_FOR_PROMPT_SWEEP" \
                --request-rate inf > "$LOG_FILE" 2>&1
        fi
    done

    # --- 2. Concurrency Sweep ---
    LOG_DIR_CONCURRENCY="$BASE_LOG_DIR/output_${output_len}/concurrency_sweep"
    mkdir -p "$LOG_DIR_CONCURRENCY"
    echo ""
    echo "--- Running Concurrency Sweep (Output Length: $output_len, Prompt Length: $FIXED_PROMPT_LENGTH_FOR_CONCURRENCY_SWEEP) ---"

    for concurrency in "${CONCURRENCIES[@]}"; do
        LOG_FILE="$LOG_DIR_CONCURRENCY/prompt-${FIXED_PROMPT_LENGTH_FOR_CONCURRENCY_SWEEP}-concurrency-${concurrency}.log"

        if [ -f "$LOG_FILE" ]; then
            echo "Skipping: Log file exists at $LOG_FILE"
        else
            echo "Benchmarking: Concurrency=$concurrency. Logging to $LOG_FILE"
            "$PYTHON_EXEC" -m sglang.bench_serving \
                --backend sglang \
                --host 127.0.0.1 --port "$PORT" \
                --dataset-name random \
                --random-input-len "$FIXED_PROMPT_LENGTH_FOR_CONCURRENCY_SWEEP" \
                --random-output-len "$output_len" \
                --num-prompts "$NUM_PROMPTS" \
                --max-concurrency "$concurrency" \
                --request-rate inf > "$LOG_FILE" 2>&1
        fi
    done
done

# --- 3. Long Prompt Concurrency Sweep ---
LOG_DIR_LONG_PROMPT="$BASE_LOG_DIR/output_10/long_prompt_concurrency_sweep"
mkdir -p "$LOG_DIR_LONG_PROMPT"
echo ""
echo "--- Running Long Prompt Concurrency Sweep (Output Length: 10, Prompt Length: 200000) ---"

for concurrency in "${CONCURRENCIES[@]}"; do
    LOG_FILE="$LOG_DIR_LONG_PROMPT/prompt-200000-concurrency-${concurrency}.log"

    if [ -f "$LOG_FILE" ]; then
        echo "Skipping: Log file exists at $LOG_FILE"
    else
        echo "Benchmarking: Concurrency=$concurrency. Logging to $LOG_FILE"
        "$PYTHON_EXEC" -m sglang.bench_serving \
            --backend sglang --host 127.0.0.1 --port "$PORT" --dataset-name random \
            --random-input-len 200000 --random-output-len 10 --num-prompts "$NUM_PROMPTS" \
            --max-concurrency "$concurrency" --request-rate inf > "$LOG_FILE" 2>&1
    fi
done

echo "Benchmark suite finished."
