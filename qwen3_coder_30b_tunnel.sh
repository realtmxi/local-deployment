#!/bin/bash

# ============================================
# Qwen3-Coder-30B Reverse Tunnel (autossh)
# ============================================

set -euo pipefail

PORT="${PORT:-8003}"
REMOTE_SSH_URL="${REMOTE_SSH_URL:-murphy@freeinference.org}"
REMOTE_BIND_HOST="${REMOTE_BIND_HOST:-0.0.0.0}"

# autossh behavior:
# - AUTOSSH_GATETIME=0: restart immediately after early failures
# - AUTOSSH_POLL=30: health-check interval (seconds)
export AUTOSSH_GATETIME="${AUTOSSH_GATETIME:-0}"
export AUTOSSH_POLL="${AUTOSSH_POLL:-30}"

echo "Starting autossh reverse tunnel..."
echo "  Remote: ${REMOTE_SSH_URL}"
echo "  Tunnel: ${REMOTE_BIND_HOST}:${PORT} -> localhost:${PORT}"

exec autossh -M 0 -N \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=no \
    -R "${REMOTE_BIND_HOST}:${PORT}:localhost:${PORT}" \
    "${REMOTE_SSH_URL}"
