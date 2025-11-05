#!/bin/bash

#SBATCH --job-name=sglang-server
#SBATCH --output=log/sglang_llama_3b_%j.log
#SBATCH --error=log/sglang_llama_3b_%j.err
#SBATCH --nodes=1
#SBATCH --gres=gpu
#SBATCH --mem=64G
#SBATCH --time=11:30:00
#SBATCH --partition=gpu_test

PORT=8001
MODEL_PATH=/n/netscratch/juncheng_lab/yiyuliu/llm_models/Llama-3.2-3B-Instruct
TP_SIZE=1
REMOTE_SSH_URL=yiyu@freeinference.org


bash "/n/juncheng_lab/Lab/llm-workload/production_scripts/service.sh" $MODEL_PATH $PORT $TP_SIZE $REMOTE_SSH_URL

