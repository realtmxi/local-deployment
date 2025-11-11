#!/bin/bash

#SBATCH --job-name=sglang-server-llama-70b
#SBATCH --output=log/sglang_llama_70b_%j.log
#SBATCH --error=log/sglang_llama_70b_%j.err
#SBATCH --nodes=1
#SBATCH --gres=gpu
#SBATCH --mem=64G
#SBATCH --time=11:30:00
#SBATCH --partition=seas_gpu

PORT=12001
MODEL_PATH=/n/netscratch/juncheng_lab/muxint/llm_models/meta-llama_Llama-3.3-70B-Instruct
TP_SIZE=4
REMOTE_SSH_URL=yiyu@freeinference.org


bash "/n/juncheng_lab/Lab/llm-workload/production_scripts/service_fasrc.sh" $MODEL_PATH $PORT $TP_SIZE $REMOTE_SSH_URL

