#!/bin/bash

# ============================================
# GLM-4.7-Flash Deployment (Docker + vLLM)
# ============================================
#
# Model: cyankiwi/GLM-4.7-Flash-AWQ-4bit
# GPU: NVIDIA GB10 (DGX Spark, unified memory, sm_121)
# Port: 8004
# Container: scitrera/dgx-spark-vllm:0.14.0-t5
#
# Usage:
#   bash glm_4.7_flash.sh
#
# ============================================

set -e

# ============================================
# Configuration
# ============================================

MODEL_NAME="cyankiwi/GLM-4.7-Flash-AWQ-4bit"
SERVED_MODEL_NAME="glm-4.7-flash"
PORT=8004
CONTAINER_NAME="glm-4.7-flash"
DOCKER_IMAGE="scitrera/dgx-spark-vllm:0.14.0-t5"
REMOTE_SSH_URL="murphy@freeinference.org"
ENABLE_SSH_TUNNEL="${ENABLE_SSH_TUNNEL:-1}"

# Log configuration
LOG_DIR="/home/murphy/logs/vllm"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/GLM-4.7-Flash_$(date +%Y%m%d_%H%M%S).log"

# Path to patch inside the container
VLLM_ARCH_PY="/usr/local/lib/python3.12/dist-packages/vllm/transformers_utils/model_arch_config_convertor.py"

# ============================================
# Validation
# ============================================

echo "========================================="
echo "  GLM-4.7-Flash Deployment (Docker)"
echo "========================================="
echo ""

if ! command -v docker &> /dev/null; then
    echo "Error: docker not found"
    exit 1
fi

echo "Configuration:"
echo "  Model:         $MODEL_NAME"
echo "  Served Name:   $SERVED_MODEL_NAME"
echo "  Port:          $PORT"
echo "  Container:     $CONTAINER_NAME"
echo "  Image:         $DOCKER_IMAGE"
echo "  SSH Tunnel:    $REMOTE_SSH_URL"
echo "  Tunnel Mode:   $([ "$ENABLE_SSH_TUNNEL" = "1" ] && echo "enabled" || echo "disabled (managed externally)")"
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
# Start vLLM Server (Docker)
# ============================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting vLLM server in Docker..." | tee -a "$LOG_FILE"

docker run \
    --gpus all \
    --privileged \
    --name "$CONTAINER_NAME" \
    --network host \
    --ipc host \
    --restart unless-stopped \
    -v "${HOME}/.cache/huggingface:/root/.cache/huggingface" \
    -d \
    "$DOCKER_IMAGE" \
    bash -c "
        # Patch vLLM: add glm4_moe_lite to model architecture config
        sed -i 's/\"pangu_ultra_moe_mtp\",/\"pangu_ultra_moe_mtp\",\n            \"glm4_moe_lite\",/' $VLLM_ARCH_PY && \
        vllm serve $MODEL_NAME \
            --gpu-memory-utilization 0.70 \
            --tool-call-parser glm47 \
            --reasoning-parser glm45 \
            --enable-auto-tool-choice \
            --served-model-name $SERVED_MODEL_NAME \
            --max-model-len 202752 \
            --max-num-batched-tokens 8192 \
            --host 0.0.0.0 \
            --port $PORT
    " 2>&1 | tee -a "$LOG_FILE"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Container $CONTAINER_NAME started" | tee -a "$LOG_FILE"

# Follow container logs in background
docker logs -f "$CONTAINER_NAME" 2>&1 | tee -a "$LOG_FILE" &
LOGS_PID=$!

# ============================================
# Start SSH Tunnel
# ============================================

if [ "$ENABLE_SSH_TUNNEL" = "1" ]; then
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
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SSH tunnel disabled (ENABLE_SSH_TUNNEL=$ENABLE_SSH_TUNNEL)" | tee -a "$LOG_FILE"
fi

echo ""
echo "========================================="
echo "  Service is running"
echo "========================================="
echo ""

if [ "$ENABLE_SSH_TUNNEL" = "1" ]; then
    echo "Systemd will restart if container or SSH tunnel exits."
else
    echo "Systemd will restart if container exits."
fi
echo ""

# Wait for container to exit (or tunnel to die)
set +e
docker wait "$CONTAINER_NAME" &
CONTAINER_WAIT_PID=$!

if [ "$ENABLE_SSH_TUNNEL" = "1" ]; then
    wait -n $CONTAINER_WAIT_PID $TUNNEL_PID 2>/dev/null || wait $CONTAINER_WAIT_PID $TUNNEL_PID
    EXIT_CODE=$?
else
    wait $CONTAINER_WAIT_PID
    EXIT_CODE=$?
fi
set -e
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Process exited with code: $EXIT_CODE"
exit $EXIT_CODE
