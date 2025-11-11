#!/bin/bash

if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <model_path> <port> <tp_size> <remote_ssh_url>"
    echo "Example: $0 /path/to/model 8001 1 user@remotehost"
    exit 1
fi

MODEL_PATH=$1
PORT=$2
TP_SIZE=$3
REMOTE_SSH_URL=$4

# --- Master Cleanup Function ---
# This is called when the slurm job is cancelled. It kills the manager functions.
cleanup() {
    echo "Master cleanup: Terminating manager processes..."
    # Check if PIDs are set before trying to kill
    if [ ! -z "$SGLANG_MGR_PID" ]; then
        kill $SGLANG_MGR_PID 2>/dev/null
        echo "Killed SGLang manager (PID: $SGLANG_MGR_PID)"
    fi
    if [ ! -z "$TUNNEL_MGR_PID" ]; then
        kill $TUNNEL_MGR_PID 2>/dev/null
        echo "Killed SSH tunnel manager (PID: $TUNNEL_MGR_PID)"
    fi
}

# Trap the script's exit signal to ensure the master cleanup runs.
trap cleanup EXIT


### --- Independent Process Managers ---

# 1. Manager for the SGLang Server
manage_sglang() {
    local SGLANG_PID
    # This trap ensures that if this manager function is killed, its child process is also killed.
    trap 'echo "[SGLANG_MGR] Exiting, killing child process $SGLANG_PID"; kill $SGLANG_PID 2>/dev/null; exit' SIGTERM EXIT

    while true; do
        echo "[SGLANG_MGR] Starting SGLang server..."
        /n/juncheng_lab/Lab/llm-workload/.venv/bin/python3 -m sglang.launch_server \
            --model-path "$MODEL_PATH" \
            --host 0.0.0.0 \
            --port "$PORT" \
            --tp-size "$TP_SIZE" \
            --enable-metrics &
        SGLANG_PID=$!
        echo "[SGLANG_MGR] SGLang server started with PID: $SGLANG_PID"
        wait $SGLANG_PID
        echo "[SGLANG_MGR] SGLang server (PID: $SGLANG_PID) has stopped. Restarting in 15 seconds..."
        sleep 15
    done
}

# 2. Manager for the SSH Tunnel
manage_tunnel() {
    local TUNNEL_PID
    trap 'echo "[TUNNEL_MGR] Exiting, killing child process $TUNNEL_PID"; kill $TUNNEL_PID 2>/dev/null; exit' SIGTERM EXIT

    while true; do
        echo "[TUNNEL_MGR] Starting SSH tunnel..."
        ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=60 -R "0.0.0.0:${PORT}:localhost:${PORT}" "$REMOTE_SSH_URL" &
        TUNNEL_PID=$!
        echo "[TUNNEL_MGR] SSH tunnel started with PID: $TUNNEL_PID"
        wait $TUNNEL_PID
        echo "[TUNNEL_MGR] SSH tunnel (PID: $TUNNEL_PID) has stopped. Restarting in 15 seconds..."
        sleep 15
    done
}


### --- Job Preparation ---
echo "Starting Slurm job for SGLang Server"
echo "Job ID: $SLURM_JOB_ID"
echo "Running on node: $(hostname)"
echo "Allocated GPU: $CUDA_VISIBLE_DEVICES"

### --- Load Essential Modules ---
module load cuda
module load gcc/12.2.0-fasrc01

### --- Main Execution Block ---
# Launch both manager functions in the background
manage_sglang &
SGLANG_MGR_PID=$!
echo "SGLang manager process started with PID: $SGLANG_MGR_PID"

manage_tunnel &
TUNNEL_MGR_PID=$!
echo "SSH tunnel manager process started with PID: $TUNNEL_MGR_PID"

# Wait for both manager processes to exit. This script will effectively pause here
# until the job is cancelled or hits its time limit.
echo "Main script is now waiting for manager processes to exit."
wait $SGLANG_MGR_PID $TUNNEL_MGR_PID


