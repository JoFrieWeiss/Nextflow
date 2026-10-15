#!/bin/bash

# Cluster-specific SBATCH options -> adjust to your HPC cluster
#SBATCH --account=<your_account>
#SBATCH --job-name=nf-pipeline
#SBATCH --partition=<your_partition>
#SBATCH --time=48:00:00
# SBATCH --qos=<your_qos> # optional, if your cluster uses QoS
#SBATCH --mem=50G
#SBATCH --cpus-per-task=4

module load nextflow/23.10.0
module load r/4.2.2
nextflow run /path/to/nf-holi.nf -resume # set path to your project nextflow pipeline
module unload r/4.2.2
