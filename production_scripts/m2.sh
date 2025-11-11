#!/bin/bash

#SBATCH --job-name=sglang-server
#SBATCH --output=log/sglang_glm_4.5_%j.log
#SBATCH --error=log/sglang_glm_4.5_%j.err
#SBATCH --nodes=1
#SBATCH -c 32
#SBATCH --gres=gpu:nvidia_h200:4
#SBATCH --mem=512G
#SBATCH --time=6-23:30:00
#SBATCH --partition=seas_gpu

PORT=12004
MODEL_PATH=/disk/models/MiniMax-M2
TP_SIZE=4
REMOTE_SSH_URL=yiyu@freeinference.org


bash "production_scripts/service.sh" $MODEL_PATH $PORT $TP_SIZE $REMOTE_SSH_URL

