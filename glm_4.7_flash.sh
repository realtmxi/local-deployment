#!/bin/bash

# ============================================
# GLM-4.7-Flash Deployment (llama.cpp)
# ============================================
#
# Model: GLM-4.7-Flash Q8_0 GGUF (single GPU)
# GPU: Single RTX PRO 6000 Blackwell (96GB)
# Port: 8004
#
# Note: sglang and vLLM both fail on Blackwell sm_120
# for this model's MLA attention, so we use llama.cpp.
#
# Usage:
#   bash glm_4.7_flash.sh
#
# ============================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================
# Configuration
# ============================================

MODEL_PATH="/scratch/murphy/models/GLM-4.7-Flash-GGUF/zai-org_GLM-4.7-Flash-Q8_0.gguf"
LLAMA_SERVER="${SCRIPT_DIR}/bin/llama-server"
PORT=8004
REMOTE_SSH_URL="murphy@freeinference.org"

# llama-server options
CTX_SIZE=16384
N_GPU_LAYERS=999

# Log configuration
LOG_DIR="/scratch/murphy/logs/llama-cpp"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/GLM-4.7-Flash_$(date +%Y%m%d_%H%M%S).log"

# ============================================
# GPU Configuration
# ============================================

# Use single GPU (GPU 1, GPU 0 is used by Qwen3-Coder-30B)
export CUDA_VISIBLE_DEVICES=1

# ============================================
# Validation
# ============================================

echo "========================================="
echo "  GLM-4.7-Flash Deployment (llama.cpp)"
echo "========================================="
echo ""

if [ ! -f "$LLAMA_SERVER" ]; then
    echo "Error: llama-server binary not found at $LLAMA_SERVER"
    exit 1
fi

if [ ! -f "$MODEL_PATH" ]; then
    echo "Error: Model file not found: $MODEL_PATH"
    exit 1
fi

echo "Configuration:"
echo "  Model:         $MODEL_PATH"
echo "  Port:          $PORT"
echo "  Context Size:  $CTX_SIZE"
echo "  GPU Layers:    $N_GPU_LAYERS"
echo "  SSH Tunnel:    $REMOTE_SSH_URL"
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

    if [ ! -z "$SERVER_PID" ]; then
        echo "Stopping llama-server (PID: $SERVER_PID)..."
        kill $SERVER_PID 2>/dev/null || true
    fi

    if [ ! -z "$TUNNEL_PID" ]; then
        echo "Stopping SSH tunnel (PID: $TUNNEL_PID)..."
        kill $TUNNEL_PID 2>/dev/null || true
    fi

    echo "Cleanup complete."
}

trap cleanup SIGINT SIGTERM EXIT

# ============================================
# Start llama-server
# ============================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting llama-server..." | tee -a "$LOG_FILE"

"$LLAMA_SERVER" \
    --model "$MODEL_PATH" \
    --port "$PORT" \
    --ctx-size "$CTX_SIZE" \
    --n-gpu-layers "$N_GPU_LAYERS" \
    --flash-attn on \
    --jinja \
    --host 0.0.0.0 2>&1 | tee -a "$LOG_FILE" &

SERVER_PID=$!
echo "[$(date '+%Y-%m-%d %H:%M:%S')] llama-server started with PID: $SERVER_PID" | tee -a "$LOG_FILE"

# ============================================
# Start SSH Tunnel
# ============================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting SSH tunnel..." | tee -a "$LOG_FILE"
echo "Forwarding port $PORT to $REMOTE_SSH_URL"

ssh -N \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=60 \
    -o StrictHostKeyChecking=no \
    -R "0.0.0.0:${PORT}:localhost:${PORT}" \
    "$REMOTE_SSH_URL" &

TUNNEL_PID=$!
echo "[$(date '+%Y-%m-%d %H:%M:%S')] SSH tunnel started with PID: $TUNNEL_PID" | tee -a "$LOG_FILE"

echo ""
echo "========================================="
echo "  Service is running"
echo "========================================="
echo ""
echo "Systemd will restart if any process exits."
echo ""

# Wait for either process to exit (then systemd will restart the whole service)
wait -n $SERVER_PID $TUNNEL_PID 2>/dev/null || wait $SERVER_PID $TUNNEL_PID
EXIT_CODE=$?
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Process exited with code: $EXIT_CODE"
exit $EXIT_CODE
