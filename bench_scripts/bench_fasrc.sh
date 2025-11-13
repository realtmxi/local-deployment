#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <port>"
    echo "This script runs a benchmark against the SGLang server."
    exit 1
fi

PORT=$1

/n/juncheng_lab/Lab/llm-workload/.venv/bin/python3 -m sglang.bench_serving \
  --backend sglang \
  --host 127.0.0.1 --port "$PORT" \
  --num-prompts 1000
  