#!/bin/bash

#SBATCH --job-name=sglang-server
#SBATCH --output=log/sglang_glm_4.5_%j.log
#SBATCH --error=log/sglang_glm_4.5_%j.err
#SBATCH --nodes=1
#SBATCH --gres=gpu
#SBATCH --mem=64G
#SBATCH --time=11:30:00
#SBATCH --partition=seas_gpu

PORT=12002
MODEL_PATH=/n/netscratch/juncheng_lab/muxint/llm_models/zai-org_GLM-4.5-Air
TP_SIZE=4
REMOTE_SSH_URL=yiyu@freeinference.org


bash "/n/juncheng_lab/Lab/llm-workload/production_scripts/service_fasrc.sh" $MODEL_PATH $PORT $TP_SIZE $REMOTE_SSH_URL

