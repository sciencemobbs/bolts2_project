#!/bin/bash
# Submit Boltz jobs for all YAML files in a directory

# ============================================================================
# CONFIGURATION
# ============================================================================

# Directory containing YAML files
YAML_DIR="boltz_inputs"

# Output directory for SLURM logs
LOG_DIR="slurm_logs"

# SLURM configuration
ACCOUNT="se85"
QOS="sexton01"
RESERVATION="sexton"
NODELIST="m3t007"
NTASKS=1
CPUS_PER_TASK=8
NTASKS_PER_NODE=1
MEM="64G"
TIME="01:00:00"
PARTITION="sexton"
GRES="gpu:1"

# Boltz configuration
#CONDA_ENV="boltz"
CACHE_DIR="/fs04/scratch2/nx54/jmobbs/docking/cache/"
USE_MSA_SERVER=""  # Set to "" to disable
#USE_MSA_SERVER="--use_msa_server"

# ============================================================================
# OPTIONAL BOLTZ ARGUMENTS
# ============================================================================

# Enable processing threads (matches CPU count requested)
PROCESSING_THREADS=true

# Enable override flag
OVERRIDE=false

# Output format: PDB or mmcif
OUTPUT_FORMAT="PDB"

# ============================================================================

# Create log directory
mkdir -p "$LOG_DIR"

# Check if YAML directory exists
if [ ! -d "$YAML_DIR" ]; then
    echo "Error: Directory '$YAML_DIR' not found"
    exit 1
fi

# Count YAML files
YAML_COUNT=$(find "$YAML_DIR" -name "*.yaml" | wc -l)

if [ "$YAML_COUNT" -eq 0 ]; then
    echo "Error: No YAML files found in '$YAML_DIR'"
    exit 1
fi

echo "============================================================"
echo "BOLTZ SLURM JOB SUBMITTER"
echo "============================================================"
echo "Found $YAML_COUNT YAML files in $YAML_DIR"
echo "Log directory: $LOG_DIR/"
echo "Cache directory: $CACHE_DIR"
echo "============================================================"
echo ""

# Counter for submitted jobs
SUBMITTED=0
FAILED=0

# Loop through all YAML files
for YAML_FILE in "$YAML_DIR"/*.yaml; do
    # Get filename without path and extension
    BASENAME=$(basename "$YAML_FILE" .yaml)
    
    # Set job name and log files
    JOB_NAME="boltz_$BASENAME"
    OUTPUT_LOG="$LOG_DIR/${BASENAME}.out"
    ERROR_LOG="$LOG_DIR/${BASENAME}.err"
    
    # Submit job
    JOB_ID=$(sbatch <<EOF
#!/bin/bash
#SBATCH --job-name=$JOB_NAME
#SBATCH --account=$ACCOUNT
#SBATCH --qos=$QOS
#SBATCH --reservation=$RESERVATION
#SBATCH --nodelist=$NODELIST
#SBATCH --ntasks=$NTASKS
#SBATCH --cpus-per-task=$CPUS_PER_TASK
#SBATCH --ntasks-per-node=$NTASKS_PER_NODE
#SBATCH --mem=$MEM
#SBATCH --time=$TIME
#SBATCH --partition=$PARTITION
#SBATCH --gres=$GRES
#SBATCH --output=$OUTPUT_LOG
#SBATCH --error=$ERROR_LOG

# Print job information
echo "Job started at: \$(date)"
echo "Running on node: \$(hostname)"
echo "Job ID: \$SLURM_JOB_ID"
echo "YAML file: $YAML_FILE"
echo ""

# Activate conda environment and run Boltz
module load miniforge3/24.3.0-0
conda activate boltz2

# Build optional arguments array
BOLTZ_ARGS=("$YAML_FILE")

# Add MSA server if specified
if [ ! -z "$USE_MSA_SERVER" ]; then
    BOLTZ_ARGS+=("$USE_MSA_SERVER")
fi

# Add cache directory
BOLTZ_ARGS+=("--cache" "$CACHE_DIR")

# Add processing threads if enabled
if [ "$PROCESSING_THREADS" = true ]; then
    BOLTZ_ARGS+=("--preprocessing-threads" "$CPUS_PER_TASK")
fi

# Add override if enabled
if [ "$OVERRIDE" = true ]; then
    BOLTZ_ARGS+=("--override")
fi

# Add output format if specified
if [ ! -z "$OUTPUT_FORMAT" ]; then
    OUTPUT_FORMAT_LOWER=\$(echo "$OUTPUT_FORMAT" | tr '[:upper:]' '[:lower:]')
    BOLTZ_ARGS+=("--output_format" "\$OUTPUT_FORMAT_LOWER")
fi

# Run Boltz with all arguments
srun boltz predict "\${BOLTZ_ARGS[@]}"

# Print completion
echo ""
echo "Job completed at: \$(date)"
echo "done"
EOF
)
    
    # Check if submission was successful
    if [ $? -eq 0 ]; then
        # Extract job ID from sbatch output
        JOB_NUM=$(echo "$JOB_ID" | awk '{print $NF}')
        echo "✓ Submitted: $(basename $YAML_FILE) (Job ID: $JOB_NUM)"
        ((SUBMITTED++))
    else
        echo "✗ Failed: $(basename $YAML_FILE)"
        ((FAILED++))
    fi
done

echo ""
echo "============================================================"
echo "SUBMISSION SUMMARY"
echo "============================================================"
echo "Successfully submitted: $SUBMITTED jobs"
echo "Failed submissions: $FAILED jobs"
echo ""
echo "Boltz command configuration:"
echo "  Processing threads: $PROCESSING_THREADS (CPUs: $CPUS_PER_TASK)"
echo "  Override: $OVERRIDE"
echo "  Output format: $OUTPUT_FORMAT"
if [ ! -z "$USE_MSA_SERVER" ]; then
    echo "  MSA server: enabled"
else
    echo "  MSA server: disabled"
fi
echo "============================================================"
echo ""
echo "Monitor jobs with: squeue -u \$USER"
echo "View logs in: $LOG_DIR/"
echo "============================================================"