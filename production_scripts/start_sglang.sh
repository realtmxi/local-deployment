#!/bin/bash

# Start the sgLang server

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <port> <tp_size>"
    echo "The script will start the sgLang server on the specified port with the given tensor parallel size."
    exit 1
fi

MODEL_PATH=$1
PORT=$2
TP_SIZE=$3

/n/juncheng_lab/Lab/llm-workload/.venv/bin/python3 -m sglang.launch_server \
    --model-path "$MODEL_PATH" \
    --host 0.0.0.0 \
    --port "$PORT" \
    --tp-size "$TP_SIZE" \
    --enable-metrics
