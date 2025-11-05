#!/bin/bash

# This script launches the SGLang server job and then chains itself to run again
# after the server job completes, creating a persistent service.

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/script.sh"
    exit 1
fi

echo "Launcher starting..."

SCRIPT="$1"

# Submit the main server job and capture the output
OUTPUT=$(sbatch "$SCRIPT")

# Check if the submission was successful
if [ $? -ne 0 ]; then
    echo "Failed to submit $SCRIPT. Aborting."
    exit 1
fi

# Extract the job ID from the sbatch output (e.g., "Submitted batch job 12345")
JOB_ID=$(echo $OUTPUT | awk '{print $4}')

echo "Script submitted with Job ID: $JOB_ID"

# Submit this launcher script again, but make it dependent on the completion of the server job.
# This creates the chain.
sbatch --dependency=afterany:$JOB_ID "$0" "$SCRIPT"

echo "Chained launcher job. It will run after job $JOB_ID completes."

