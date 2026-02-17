#!/bin/bash

# ============================================
# BGE-M3 Embedding Deployment (sglang)
# ============================================
#
# Model: BAAI/bge-m3 (XLM-RoBERTa, ~568M params)
# GPU: RTX PRO 6000 Blackwell (shared with GLM-4.7-Flash on GPU 1)
# Port: 8005
#
# Note: sglang's roberta.py has a position assertion bug that
# crashes on health checks. We patch line 95 to disable it.
# See .venv/lib/python3.12/site-packages/sglang/srt/models/roberta.py
#
# Usage:
#   bash bge_m3.sh
#
# ============================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================
# Configuration
# ============================================

MODEL_PATH="/scratch/murphy/models/bge-m3"
PORT=8005
REMOTE_SSH_URL="murphy@freeinference.org"
PYTHON_VENV="${SCRIPT_DIR}/.venv"
PYTHON_BIN="${PYTHON_VENV}/bin/python3"

# Log configuration
LOG_DIR="/scratch/murphy/logs/sglang"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/bge-m3_$(date +%Y%m%d_%H%M%S).log"

# ============================================
# GPU Configuration
# ============================================

# Use GPU 1 (shared with GLM-4.7-Flash, BGE-M3 only needs ~3GB)
export CUDA_VISIBLE_DEVICES=1

# ============================================
# Validation
# ============================================

echo "========================================="
echo "  BGE-M3 Embedding Deployment (sglang)"
echo "========================================="
echo ""

if [ ! -f "$PYTHON_BIN" ]; then
    echo "Error: Python binary not found at $PYTHON_BIN"
    exit 1
fi

if [ ! -d "$MODEL_PATH" ]; then
    echo "Error: Model path not found: $MODEL_PATH"
    exit 1
fi

echo "Configuration:"
echo "  Model:         $MODEL_PATH"
echo "  Port:          $PORT"
echo "  SSH Tunnel:    $REMOTE_SSH_URL"
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

    if [ ! -z "$SERVER_PID" ]; then
        echo "Stopping sglang server (PID: $SERVER_PID)..."
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
# Start sglang Embedding Server
# ============================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting sglang embedding server..." | tee -a "$LOG_FILE"

$PYTHON_BIN -m sglang.launch_server \
    --model-path "$MODEL_PATH" \
    --served-model-name "bge-m3" \
    --host 0.0.0.0 \
    --port "$PORT" \
    --is-embedding \
    --mem-fraction-static 0.10 \
    2>&1 | tee -a "$LOG_FILE" &

SERVER_PID=$!
echo "[$(date '+%Y-%m-%d %H:%M:%S')] sglang server started with PID: $SERVER_PID" | tee -a "$LOG_FILE"

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
