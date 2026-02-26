#!/bin/bash

# ============================================
# BGE-M3 Embedding Deployment (Docker + sglang)
# ============================================
#
# Model: BAAI/bge-m3 (XLM-RoBERTa, ~568M params)
# GPU: NVIDIA GB10 (DGX Spark, unified memory, sm_121)
# Port: 8005
# Container: lmsysorg/sglang:spark (built for Blackwell GB10)
#
# Note: sglang's roberta.py has a position assertion bug that
# crashes on health checks. We patch it at container startup.
#
# Usage:
#   bash bge_m3.sh
#
# ============================================

set -e

# ============================================
# Configuration
# ============================================

MODEL_PATH="/home/murphy/models/bge-m3"
PORT=8005
CONTAINER_NAME="bge-m3-embedding"
DOCKER_IMAGE="lmsysorg/sglang:spark"
REMOTE_SSH_URL="murphy@freeinference.org"

# Log configuration
LOG_DIR="/home/murphy/logs/sglang"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/bge-m3_$(date +%Y%m%d_%H%M%S).log"

# Path to roberta.py inside the container
ROBERTA_PY="/sgl-workspace/sglang/python/sglang/srt/models/roberta.py"

# ============================================
# Validation
# ============================================

echo "========================================="
echo "  BGE-M3 Embedding Deployment (Docker)"
echo "========================================="
echo ""

if [ ! -d "$MODEL_PATH" ]; then
    echo "Error: Model path not found: $MODEL_PATH"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "Error: docker not found"
    exit 1
fi

echo "Configuration:"
echo "  Model:         $MODEL_PATH"
echo "  Port:          $PORT"
echo "  Container:     $CONTAINER_NAME"
echo "  Image:         $DOCKER_IMAGE"
echo "  SSH Tunnel:    $REMOTE_SSH_URL"
echo "  Hostname:      $(hostname)"
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

    echo "Stopping container $CONTAINER_NAME..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true

    if [ ! -z "$TUNNEL_PID" ]; then
        echo "Stopping SSH tunnel (PID: $TUNNEL_PID)..."
        kill $TUNNEL_PID 2>/dev/null || true
    fi

    echo "Cleanup complete."
}

trap cleanup SIGINT SIGTERM EXIT

# Remove stale container if exists
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

# ============================================
# Start sglang Embedding Server (Docker)
# ============================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting sglang embedding server in Docker..." | tee -a "$LOG_FILE"

docker run \
    --gpus all \
    --name "$CONTAINER_NAME" \
    --network host \
    --restart unless-stopped \
    -v "${MODEL_PATH}:/models/bge-m3:ro" \
    -d \
    "$DOCKER_IMAGE" \
    bash -c "
        # Patch roberta.py: disable position assertion that crashes on health checks
        sed -i 's/assert torch.equal(positions, expected_pos)/# assert torch.equal(positions, expected_pos)  # patched/' $ROBERTA_PY && \
        python3 -m sglang.launch_server \
            --model-path /models/bge-m3 \
            --served-model-name bge-m3 \
            --host 0.0.0.0 \
            --port $PORT \
            --is-embedding \
            --mem-fraction-static 0.10
    " 2>&1 | tee -a "$LOG_FILE"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Container $CONTAINER_NAME started" | tee -a "$LOG_FILE"

# Follow container logs in background
docker logs -f "$CONTAINER_NAME" 2>&1 | tee -a "$LOG_FILE" &
LOGS_PID=$!

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

# Wait for container to exit or tunnel to die
docker wait "$CONTAINER_NAME" &
CONTAINER_WAIT_PID=$!

wait -n $CONTAINER_WAIT_PID $TUNNEL_PID 2>/dev/null || wait $CONTAINER_WAIT_PID $TUNNEL_PID
EXIT_CODE=$?
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Process exited with code: $EXIT_CODE"
exit $EXIT_CODE
