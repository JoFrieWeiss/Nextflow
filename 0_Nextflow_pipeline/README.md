# How to use Nextflow in combination with EnviHoli

The workflow is a **Nextflow** implementation of the **EnviHoli** metagenomic pipeline (Zenodo: 10.5281/zenodo.17974857) and reuses its R scripts (see scripts/README.md).

The pipeline was run on a SLURM-based HPC cluster using environment modules (`module load`). To run it on another SLURM-based system, the cluster-specific settings need to be adapted.

---

## Table of contents

- [1. Pipeline Overview](#1-pipeline-overview)
- [2. Create a Nextflow working directory](#2-create-a-nextflow-working-directory)
- [3. Processing metagenomic raw data](#3-processing-metagenomic-raw-data)
  - [3.1 Project setup](#31-project-setup-recommended)
  - [3.2 Prepare raw data and metadata](#32-prepare-raw-data-and-metadata)
  - [3.3 Adjust parameters and links](#33-adjust-parameters-and-links)
- [4. Run the pipeline](#4-run-the-pipeline)
- [5. Debugging](#5-debugging)
- [6. Error codes](#6-error-codes)

---

## 1. Pipeline Overview
| Step	| Process(es)	| Tool | Notes |
|------|---------|------------|-----------|
| Quality check of raw reads | fastqc_pre |	FastQC | |	
| First deduplication	| clumpify	| BBTools `clumpify.sh` |	dedupe=t optical=f |
| Adapter trimming, quality filtering, read merging	| fastp | fastp | min. length 30 bp, low-complexity filter, poly-G/X trimming, see src/nf-holi.nf for all parameters |
| Second deduplication	| dedupe	| BBTools `dedupe.sh` |	separately for R1, R2 and merged reads |
| Quality check of processed reads |	fastqc_post	| FastQC | |	
| Alignment of merged reads against each reference database	| align, align_dedupe	| Bowtie2, SAMtools	| `-k 1000`, end-to-end; align_dedupe additionally removes duplicate `@SQ` headers |
| Merge and sort alignments by read name	| merge_sort |	SAMtools, `gz-sort`	| |
| Taxonomic classification (LCA) and damage estimation	| metaDMG	| metaDMG	| `--custom-database --bayesian` |
| Post-processing	| post_metaDMG_LCA, combine_lca, mismatch, combine_dmg_out	| R	scripts in scripts/ | |
| QC reports	| multiqc, multiqc_sample, multiqc_merged |	MultiQC	| |

---

## 2. Create a Nextflow working directory

Nextflow works in dedicated working directories with unique naming. These working directories can be located separate from where you store the corresponding Nextflow code, log files, Nextflow reports and Nextflow run outputs. This gives you the opportunity to run the processes where you have the highest available disk space and speed but keep the code and log files in a place that allows long-term storage.

It is recommended to create **one overarching Nextflow working directory** in which each Nextflow pipeline you run gets its own project working directory. Create it where you have the highest available disk space.

---

## 3. Processing metagenomic raw data

### 3.1 Project setup (recommended)

Create a project folder for **each core** in a directory that does not get deleted after some time.
Copy the whole `0_Nextflow_pipeline` directory of the Nextflow EnviHoli pipeline into your created directory.

The pipeline expects a project directory (params.baseDir) with the following layout:

```text
<project directory>/
├── data/
│   ├── raw_data/         # raw reads (e.g. symbolic links)
│   └── processed_data/   # intermediate files (created by the pipeline)
├── scripts/              # copy of scripts/ from this repository (analysis / helper scripts)
└── src/                  # copy of src/ from this repository (config, sbatch script and the Nextflow pipeline (.nf))
```

If you copied the whole pipeline directory as shown above, this structure is already in place.

### 3.2 Prepare raw data and metadata

Create an extra directory with **symbolic links** to the original data:

```bash
ln -s <path to original data> <path to your raw data directory>
```

Check if the symbolic links work:

```bash
ls -l    # should show you the links and the paths to the original data
```

**(Optional) change file endings** of your symbolic links if necessary. They should end in `.R1.fastq.gz` or `.R2.fastq.gz`:

Example: 
```bash
for file in *_R[12]_001.fastq.gz; do
  newname="${file/_R1_001.fastq.gz/.R1.fastq.gz}"
  newname="${newname/_R2_001.fastq.gz/.R2.fastq.gz}"
  if [ "$file" != "$newname" ]; then
    mv "$file" "$newname"
  fi
done
```

**Prepare the metadata file:**

- A comma-separated file with at least the columns `sample` and `years`.
`sample` must match the part of the raw read file name before the first `.` (e.g. `ABC-1_S1` for `ABC-1_S1.R1.fastq.gz`) to be correctly joined in processes `combine_lca`, `mismatch` and `combine_dmg_out`.

### 3.3 Adjust parameters and links

Adjust the files in the `src` directory:

#### Database file (`db_align_sheet.csv`)
- Adjust according to your databases.
- To **exclude** a database, change the entry in the last column from `y` to `n`.

#### Config file (`nextflow.config`)
- Adjust the working directory path (first line of code).
- Do **not** use underscores `_` or spaces in the project name.
- Put the path into quotes `""`.
- Adjust according to your HPC Cluster

#### sbatch script (`nextflow.sbatch`)
- Adjust the path to the Nextflow script you want to run.
- Do **not** put it into quotes.

#### Nextflow pipeline (e.g. `nf-holi.nf`)
Set the pipeline parameters (at the top of the script):

| Parameter | What to change |
|-----------|----------------|
| `params.lake` | Name of the lake. Put in quotes `""`, best lowercase only. |
| `params.baseDir` | Project directory containing your `data`, `scripts` and `src`. Put in quotes `""`. Changing this automatically updates all other params that refer to `${params.baseDir}`, so if you copied the whole directory and kept the structure, you don't need to adjust the other paths. |
| `params.analysisDir` | Path where your output data should go. |
| `params.metaData` | Adjust to the name of the metadata file. |
| `params.taxonomyDir` | Path to where the taxonomy files are located. |
| `params.metaDMGCPP` | Path where the metaDMG-cpp binary is located. |

---

## 4. Run the pipeline

### Run from the sbatch script

1. Change into the `src` directory:
   ```bash
   cd <path to your source directory>
   ```
2. Start the Nextflow script by submitting your sbatch script:
   ```bash
   sbatch nextflow.sbatch
   ```

### Restart a failed run

Just do the same as for starting the run. Nextflow automatically resumes from the breaking point.

### Cancel a run

Cancel **only Nextflow-related** jobs. There is no neat way to do this; the best option is to cancel all jobs whose name starts with `nf-`:

```bash
squeue -u <your username> -o "%.18i %.50j" | grep 'nf-*' | awk '{print $1}' | xargs scancel
```

> ⚠️ Be careful: this will also cancel any other job whose name starts with `nf-`.

---

## 5. Debugging

- If one sample causes problems and you want to proceed without it, uncomment the following line and replace the sample IDs with your own:
  ```groovy
  //.filter { sampleID, reads1, reads -> sampleID != "<your sample ID 1>" & sampleID != "<your sample ID 2>" }
  ```
- Read the `.command.log` file in the process directory that failed. The path to this directory can be found in the sbatch log file or the latest Nextflow report. What does it tell you? Start debugging from there.

---

## 6. Error codes
A Nextflow run can fail for several reasons. Here is a short list of the most common error codes and a simplified first possible solution to resume the run.

| Code | Meaning | What to do |
|------|---------|------------|
| `134` | Job killed with an abort signal (usually after you ran `scancel`). | Start the run again. |
| `140` | Job exceeded the "wall clock" time limit. | Increase the requested time: adjust `time = ` in the Nextflow file for the failed process. |
| `143` | Something killed your process with `SIGTERM`. | Start the run again. |
| `1` | Failed, but the reason is unclear. | Try to start the run again. |
