#!/bin/bash

# ============================================
# Qwen3-Coder-30B-A3B-Instruct Deployment
# ============================================
# 
# Model: Qwen3-Coder-30B-A3B-Instruct-FP8
# GPU: Single RTX Pro 6000 (48GB)
# Port: 8003
#
# Usage:
#   bash qwen3_coder_30b.sh
#
# ============================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================
# Configuration
# ============================================

MODEL_PATH="/scratch/murphy/models/Qwen3-Coder-30B-A3B-Instruct"
PORT=8003
TP_SIZE=1
REMOTE_SSH_URL="murphy@freeinference.org"
PYTHON_VENV="${SCRIPT_DIR}/.venv"

# ============================================
# GPU Configuration (Optional)
# ============================================

# Use single GPU
export CUDA_VISIBLE_DEVICES=0

# Limit GPU power to 400W due to power constraints
# Note: murphy user doesn't have sudo access
# Please run manually with sudo before starting the service:
#   sudo nvidia-smi -i 0 -pl 400
echo "Note: Please ensure GPU power limit is set to 400W"
# sudo nvidia-smi -i 0 -pl 400

# ============================================
# Launch Service
# ============================================

echo "Deploying Qwen3-Coder-30B-A3B-Instruct..."
echo ""

bash "${SCRIPT_DIR}/service.sh" \
    "$MODEL_PATH" \
    "$PORT" \
    "$TP_SIZE" \
    "$REMOTE_SSH_URL" \
    "$PYTHON_VENV"
