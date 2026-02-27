#!/bin/bash

# SGLang Model Deployment Service
# Supports auto-restart and SSH tunnel management for standalone servers

set -e

# ============================================
# Configuration Validation
# ============================================

if [ "$#" -lt 4 ] || [ "$#" -gt 6 ]; then
    echo "Usage: $0 <model_path> <port> <tp_size> <remote_ssh_url> [python_venv] [extra_args]"
    echo ""
    echo "Arguments:"
    echo "  model_path      - Path to the model directory"
    echo "  port            - Port number for the server"
    echo "  tp_size         - Tensor parallel size (1 for single GPU)"
    echo "  remote_ssh_url  - SSH URL for tunnel (e.g., user@host)"
    echo "  python_venv     - Optional: Path to Python virtual environment"
    echo "  extra_args      - Optional: Extra arguments for sglang (e.g., '--quantization awq')"
    echo ""
    echo "Example:"
    echo "  $0 /path/to/model 8003 1 user@host /path/to/.venv '--quantization awq'"
    exit 1
fi

MODEL_PATH=$1
PORT=$2
TP_SIZE=$3
REMOTE_SSH_URL=$4
PYTHON_VENV=${5:-"$(dirname "$0")/.venv"}  # Default to script directory's .venv
EXTRA_ARGS=${6:-""}
ENABLE_SSH_TUNNEL=${ENABLE_SSH_TUNNEL:-1}

PYTHON_BIN="${PYTHON_VENV}/bin/python3"

# Log configuration
LOG_DIR="/scratch/murphy/logs/sglang"
mkdir -p "$LOG_DIR"
MODEL_NAME_FOR_LOG=$(basename "$MODEL_PATH")
LOG_FILE="${LOG_DIR}/${MODEL_NAME_FOR_LOG}_$(date +%Y%m%d_%H%M%S).log"

# ============================================
# Validation
# ============================================

echo "========================================="
echo "  SGLang Model Deployment Service"
echo "========================================="
echo ""

# Check Python environment
if [ ! -f "$PYTHON_BIN" ]; then
    echo "Error: Python binary not found at $PYTHON_BIN"
    echo "Please check your virtual environment path."
    exit 1
fi

# Check model path
if [ ! -d "$MODEL_PATH" ]; then
    echo "Error: Model path not found: $MODEL_PATH"
    exit 1
fi

echo "Configuration:"
echo "  Model Path:    $MODEL_PATH"
echo "  Port:          $PORT"
echo "  TP Size:       $TP_SIZE"
echo "  SSH Tunnel:    $REMOTE_SSH_URL"
echo "  Tunnel Mode:   $([ "$ENABLE_SSH_TUNNEL" = "1" ] && echo "enabled" || echo "disabled (managed externally)")"
echo "  Python:        $PYTHON_BIN"
echo "  Hostname:      $(hostname)"
echo "  GPU Devices:   ${CUDA_VISIBLE_DEVICES:-all}"
echo "  Log File:      $LOG_FILE"
echo ""

# ============================================
# Cleanup Handler
# ============================================

cleanup() {
    echo ""
    echo "========================================="
    echo "  Shutting down services..."
    echo "========================================="

    if [ ! -z "$SGLANG_PID" ]; then
        echo "Stopping SGLang server (PID: $SGLANG_PID)..."
        kill $SGLANG_PID 2>/dev/null || true
    fi

    if [ ! -z "$TUNNEL_PID" ]; then
        echo "Stopping SSH tunnel (PID: $TUNNEL_PID)..."
        kill $TUNNEL_PID 2>/dev/null || true
    fi

    echo "Cleanup complete."
}

trap cleanup SIGINT SIGTERM EXIT

# ============================================
# Start SGLang Server
# ============================================

start_sglang() {
    echo "" | tee -a "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SGLang] Starting server..." | tee -a "$LOG_FILE"

    # Extract model name from path (last directory name)
    MODEL_NAME=$(basename "$MODEL_PATH")

    $PYTHON_BIN -m sglang.launch_server \
        --model-path "$MODEL_PATH" \
        --served-model-name "$MODEL_NAME" \
        --host 0.0.0.0 \
        --port "$PORT" \
        --tp-size "$TP_SIZE" \
        --dp-size 1 \
        --enable-metrics \
        --mem-fraction-static 0.80 \
        $EXTRA_ARGS 2>&1 | tee -a "$LOG_FILE" &

    SGLANG_PID=$!
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SGLang] Server started with PID: $SGLANG_PID" | tee -a "$LOG_FILE"
}

# ============================================
# Start SSH Tunnel
# ============================================

start_tunnel() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Tunnel] Starting SSH tunnel..."
    echo "[Tunnel] Forwarding port $PORT to $REMOTE_SSH_URL"

    ssh -N \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=60 \
        -o StrictHostKeyChecking=no \
        -R "0.0.0.0:${PORT}:localhost:${PORT}" \
        "$REMOTE_SSH_URL" &

    TUNNEL_PID=$!
    echo "[Tunnel] SSH tunnel started with PID: $TUNNEL_PID"
}

# ============================================
# Main Execution
# ============================================

echo "Starting services..."
echo ""

# Start SGLang server
start_sglang
echo "✓ SGLang server started (PID: $SGLANG_PID)"

# Start SSH tunnel
if [ "$ENABLE_SSH_TUNNEL" = "1" ]; then
    start_tunnel
    echo "✓ SSH tunnel started (PID: $TUNNEL_PID)"
else
    echo "✓ SSH tunnel disabled in service.sh (ENABLE_SSH_TUNNEL=$ENABLE_SSH_TUNNEL)"
fi

echo ""
echo "========================================="
echo "  Service is running"
echo "========================================="
echo ""
if [ "$ENABLE_SSH_TUNNEL" = "1" ]; then
    echo "Systemd will restart if SGLang or SSH tunnel exits."
else
    echo "Systemd will restart if SGLang exits."
fi
echo ""

# Wait for process exit (then systemd will restart the service)
set +e
if [ "$ENABLE_SSH_TUNNEL" = "1" ]; then
    wait -n "$SGLANG_PID" "$TUNNEL_PID"
    EXIT_CODE=$?
else
    wait "$SGLANG_PID"
    EXIT_CODE=$?
fi
set -e
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Process exited with code: $EXIT_CODE"
exit $EXIT_CODE
