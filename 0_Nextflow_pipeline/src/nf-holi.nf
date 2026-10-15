#!/usr/bin/env nextflow

/*
 * Nextflow pipeline to run the shotgun holi pipeline
 * 
 * author: Christiane Boeckel
 */

/*
 * Set pipeline parameters
 */

params.lake             = "Example" // name of the core, will be used for file naming --> use "_" or "-" instead of spaces
params.baseDir          = "/path/to/project" // path to your project directory -> recommended to put in a directory that does not get deleted after a certain time
params.rawDataDir       = "${params.baseDir}/data/raw_data" // path to your raw data directory
params.analysisDir      = "/path/to/output/${params.lake}" // path where output should be stored
params.processedDataDir = "${params.baseDir}/data/processed_data" // path to where intermediate output data should be stored -> all files that you will delete after you don't need the intermediate files anymore
params.scripts          = "${params.baseDir}/scripts" // path to the R scripts
params.metaData         = "${params.baseDir}/src/Example_sample_file.csv" // path to the metadata sample file
params.databases        = "${params.baseDir}/src/db_align_sheet.csv" // path to the database metadata table

/*
* Set according to your taxonomic files. If you use the EnviHoli database, you can use the taxonomic files provided on Zenodo. If you use your own database, you need to provide the corresponding taxonomic files.
*/ 
// taxonomic files - as described in https://doi.org/10.5281/zenodo.17974857
params.taxonomyDir      = "/path/to/taxonomy" // path to the directory where the taxonomic files are stored
params.acc2taxFile      = "${params.taxonomyDir}/Siberian_modify_combined_acc2taxid_v1.gz"
params.namesFile        = "${params.taxonomyDir}/Siberian_names.dmp"
params.nodesFile        = "${params.taxonomyDir}/Siberian_nodes.dmp"
params.rankLineages     = "${params.taxonomyDir}/Siberian_rankedlineage.dmp"
params.fullLineages     = "${params.taxonomyDir}/Siberian_fullnamelineage.dmp"
params.taxRdata         = "${params.taxonomyDir}/Siberian_taxlineage.RData"

/*
 * Set paths to the software modules that are used in the pipeline
 */

params.metaDMGCPP = "/path/to/metaDMG-cpp" // used in process metaDMG, set to the path where the metaDMG-cpp binary is located

/*
 * check raw data sequence quality
 */

process fastqc_pre {
    executor = 'slurm'
    cpus = 2
    time = { 20.min * task.attempt }
    memory = { 1.GB * task.attempt }
    errorStrategy = { 'retry' } 
    //beforeScript = "module load ${params.fastqc}"

    publishDir "${params.analysisDir}/${sampleID}/QC/fastqc_pre", mode: 'copy'

    input:
    tuple val(sampleID), path(read1), path(read2)

    output:
    path "*fastqc*"
    tuple val(sampleID), path("*_fastqc.zip")

    script:
    """
    module load ${params.fastqc}
    fastqc -q -t ${task.cpus} ${read1} ${read2} -o .
    module unload ${params.fastqc}
    """
}



// first deduplication step
process clumpify {
    executor = 'slurm'
    cpus = 16
    time = { 40.min * task.attempt }
    memory = { 100.GB * task.attempt }
    errorStrategy = { 'retry' }

    publishDir "${params.processedDataDir}/clumpify", mode: 'symlink'

    input:
    tuple val(sampleID), path(read1), path(read2)

    output:
    tuple val(sampleID), path("*clumpify_R1.fq.gz"), path("*clumpify_R2.fq.gz")

    script:
    """
    module load ${params.bbtools}
    clumpify.sh dedupe=t optical=f in=${read1} in2=${read2} out=${sampleID}_clumpify_R1.fq.gz out2=${sampleID}_clumpify_R2.fq.gz
    module unload ${params.bbtools}
    """
}


// trimming and merging
process fastp {
    executor = 'slurm'
    cpus = 12
    time = { 10.min * task.attempt }
    memory = { 20.GB * task.attempt }
    errorStrategy = { 'retry' }

    publishDir "${params.processedDataDir}/fastp", mode: 'symlink'

    input:
    tuple val(sampleID), path(read1), path(read2)

    output:
    tuple val(sampleID), path("*_fastp_R1.fq.gz"), path("*_fastp_R2.fq.gz"), path("*_fastp_merged.fq.gz")
    tuple val(sampleID), path("*.json")

    script:
    """
    module load ${params.fastp}
    fastp --in1 ${read1} --in2 ${read2} --out1 ${sampleID}_fastp_R1.fq.gz --out2 ${sampleID}_fastp_R2.fq.gz -m --merged_out ${sampleID}_fastp_merged.fq.gz -a auto --poly_g_min_len 10 --poly_x_min_len 10 --qualified_quality_phred 15 --unqualified_percent_limit 40 --n_base_limit 5 --length_required 30 --low_complexity_filter --complexity_threshold 30 --correction --overlap_len_require 30 --overlap_diff_limit 5 --overlap_diff_percent_limit 20 -w ${task.cpus} --verbose --json=${sampleID}.json --html=${sampleID}.html
    module unload ${params.fastp}
    """
}

// second deduplication
process dedupe {
    executor = 'slurm'
    cpus = 16
    time = { 10.min * task.attempt }
    memory = { 75.GB * task.attempt }
    errorStrategy = { 'retry' }

    publishDir "${params.processedDataDir}/dedupe", mode: 'symlink'

    input:
    tuple val(sampleID), val(type), path(read)

    output:
    tuple val(sampleID), val(type), path("${sampleID}_{R1,R2,merged}.fq.gz", glob: true)

    script:
    """
    module load ${params.bbtools}
    dedupe.sh -Xmx${task.memory.giga}g in=${read} out=${sampleID}_${type}.fq.gz ac=f
    module unload ${params.bbtools}
    """
}

process fastqc_post {
    executor = 'slurm'
    cpus = 2
    time = { 10.min * task.attempt }
    memory = { 1.GB * task.attempt }
    errorStrategy = { 'retry' }

    publishDir "${params.analysisDir}/${sampleID}/QC/fastqc_post", mode: 'copy'

    input:
    tuple val(sampleID), path(read1), path(read2), path(merged)

    output:
    path "*fastqc*"
    tuple val(sampleID), path("*_fastqc.zip")
    tuple val(sampleID), path("*_merged_fastqc.zip")

    script:
    """
    module load ${params.fastqc}
    fastqc -q -t ${task.cpus} ${read1} ${read2} ${merged} -o .
    module unload ${params.fastqc}
    """
}

process align {
    executor = 'slurm'
    cpus = 64
    time = { 1.hour * task.attempt }
    memory = { 220.GB } 
    errorStrategy = { 'retry' }

    publishDir "${params.processedDataDir}/align/${sampleID}", mode: 'symlink'

    input:
    tuple val(sampleID), path(reads), val(dbID), val(dedup), path(db_path)

    output:
    tuple val(sampleID), path("*.bam")
    tuple val(sampleID), path("*.log")

    script:
    """
    module load ${params.align}
    module load ${params.view}

    (bowtie2 --threads ${task.cpus} -k 1000 -x ${dbID} -U ${reads} --no-unal -S ${sampleID}.${dbID}.sam) 2>${sampleID}.${dbID}.log
    samtools view -b ${sampleID}.${dbID}.sam > ${sampleID}.${dbID}.bam
    rm ${sampleID}.${dbID}.sam

    module unload ${params.align}
    module unload ${params.view}
    """
}

process align_dedupe {
    executor = 'slurm'
    cpus = 64
    time = { 30.min * task.attempt }
    memory = { 150.GB }
    errorStrategy = { 'retry' } 

    publishDir "${params.processedDataDir}/align/${sampleID}", mode: 'symlink'

    input:
    tuple val(sampleID), path(reads), val(dbID), val(dedup), path(db_path)

    output:
    tuple val(sampleID), path("*.bam")

    script:
    """
    module load ${params.align}
    module load ${params.view}

    # align
    (bowtie2 --threads ${task.cpus} -k 1000 -x ${dbID} -U ${reads} --no-unal -S ${sampleID}.${dbID}.sam) 2>${sampleID}.${dbID}.log
    
    # deduplicate
    ${params.scripts}/dedup_sam.py ${sampleID}.${dbID}.sam ${sampleID}.${dbID}.dedup.sam
    
    # convert sam to bam
    samtools view -bS ${sampleID}.${dbID}.dedup.sam > ${sampleID}.${dbID}.bam
    rm ${sampleID}.${dbID}.sam ${sampleID}.${dbID}.dedup.sam
    
    module unload ${params.view}
    module unload ${params.align}
    """

}

process merge_sort {
    executor = 'slurm'
    cpus = 64
    time = { 48.hour }
    memory = { 220.GB } 

    publishDir "${params.processedDataDir}/sorted", mode: 'link'

    input:
    tuple val(sampleID), path(sam_files)

    output:
    tuple val(sampleID), path("*_L30.sorted.sam.gz")

    script:
    """
    module load ${params.view}
    module load ${params.gzsort}

    # merge
    samtools merge --verbosity 5 ${sampleID}.L30.merged.sam.gz ${sam_files} -@ ${task.cpus}

    # sort
    samtools view -@ ${task.cpus} -H ${sampleID}.L30.merged.sam.gz | sed '0,/^@HD/s/SO:unsorted/SO:queryname/' | pigz > ${sampleID}.L30.Header.sam.gz
    samtools view -@ ${task.cpus} ${sampleID}.L30.merged.sam.gz | pigz > ${sampleID}.L30.alignment.sam.gz
    gz-sort -S 30G -P 30 ${sampleID}.L30.alignment.sam.gz ${sampleID}.L30.alignment.sort.sam.gz
    zcat ${sampleID}.L30.Header.sam.gz ${sampleID}.L30.alignment.sort.sam.gz | samtools view -h -o ${sampleID}_L30.sorted.sam.gz
    rm ${sampleID}.L30.Header.sam.gz ${sampleID}.L30.alignment.sam.gz ${sampleID}.L30.alignment.sort.sam.gz
    
    module unload ${params.view}
    module unload ${params.gzsort}
    """
}

process metaDMG {
    executor = 'slurm'
    cpus = 32
    time = { 24.hour * task.attempt }
    memory = { 180.GB } 
    errorStrategy = { 'ignore' }

    publishDir "${params.analysisDir}/${sampleID}/*", mode: 'copy'

    input:
    tuple val(sampleID), path(bam)

    output:
    tuple val(sampleID), path("*_metaDMG")

    script:
    """
    DMG_CPP_PATH=${params.metaDMGCPP}

    module load ${params.metaDMG}
    #==
    echo "create yaml"
    # -m cpp path
    metaDMG config ${bam} --names ${params.namesFile} --nodes ${params.nodesFile} --acc2tax ${params.acc2taxFile} --parallel-samples 1 --cores-per-sample ${task.cpus} --custom-database --bayesian --config-file config_${sampleID}.yaml -m \${DMG_CPP_PATH} -f -o ${sampleID}_metaDMG
    
    #==
    echo "compute"
    metaDMG compute config_${sampleID}.yaml

    echo "csv"
    metaDMG convert config_${sampleID}.yaml --output ${sampleID}_metaDMG/${sampleID}_metaDMGout.csv

    echo "pdf"
    metaDMG plot config_${sampleID}.yaml --output ${sampleID}_metaDMG/${sampleID}.pdf 2>error

    mv logs ${sampleID}_metaDMG
    mv config_${sampleID}.yaml ${sampleID}_metaDMG

    module unload ${params.metaDMG}
    """
}


process post_metaDMG_LCA {
    executor = 'slurm'
    cpus = 4
    time = { 5.min * task.attempt }
    memory = { 10.GB * task.attempt }
    errorStrategy = { 'retry' } 
    cache = false


    publishDir "${params.analysisDir}/Rdata/", mode: 'symlink'

    input:
    tuple val(sampleID), path(metaOutput)

    output:
    path "${sampleID}_metaDMG/lca/*_L30.lca.taxlineage.tsv"

    script:
    """
    module load ${params.rtool}
    Rscript ${params.scripts}/post-metadmg-lca.R ${sampleID}_metaDMG/lca/ ${sampleID} "_L30.lca.txt.gz" ${params.fullLineages} ${params.rankLineages} ${params.nodesFile}
    module unload ${params.rtool}
    """    
}

process combine_lca {
    executor = 'slurm'
    cpus = 4
    time = { 10.min * task.attempt }
    memory = { 100.GB * task.attempt }
    errorStrategy = { 'retry' }
    cache = false

    publishDir "${params.analysisDir}/Rdata/", mode: 'copy'

    input:
    path files

    output:
    path "*_lca_MergedData.RData"

    script:
    """
    module load ${params.rtool}
    Rscript ${params.scripts}/combine_lca.R . ".lca.taxlineage.tsv" ${params.metaData} . "${params.lake}_lca"
    module unload ${params.rtool}
    """    
}

process mismatch {
    executor = 'slurm'
    cpus = 8
    time = { 15.min * task.attempt }
    memory = { 20.GB * task.attempt }
    errorStrategy = { 'retry' }
    cache = false
    
    publishDir "${params.analysisDir}/Rdata/", mode: 'copy'

    input:
    path mismatches

    output:
    path "*_mismatch_MergedData.RData"

    script:
    """
    module load ${params.rtool}
    Rscript ${params.scripts}/mismatch.R . "_L30.mismatches.txt.gz" ${params.metaData} ${params.taxRdata} . "${params.lake}_mismatch"
    module unload ${params.rtool}
    """
}

process combine_dmg_out {
    executor = 'slurm'
    cpus = 8
    time = { 15.min * task.attempt }
    memory = { 20.GB * task.attempt }
    errorStrategy = { 'retry' }
    cache = false

    publishDir "${params.analysisDir}/Rdata/", mode: 'copy'

    input:
    path dmgout

    output:
    path "*_metaDMGout_MergedData.RData"

    script:
    """
    module load ${params.rtool}
    Rscript ${params.scripts}/combine_dmgout.R . "_metaDMGout.csv" "_L30" ${params.metaData} ${params.taxRdata} . "${params.lake}_metaDMGout" 
    module unload ${params.rtool}
    """    
}

process multiqc_merged {
    executor = 'slurm'
    cpus = 1
    time = { 10.min * task.attempt }
    memory = { 10.GB * task.attempt }
    errorStrategy = { 'retry' }

    publishDir "${params.analysisDir}/", mode: 'copy'

    input:
    path files

    output:
    file '*multiqc*'

    script:
    """
    module load ${params.multiqc}
    multiqc -n ${params.lake}_merged_multiqc_report.html -o ${params.lake}_merged_multiqc_data/ .
    module unload ${params.multiqc}
    """    
}

process multiqc_sample {
    executor = 'slurm'
    cpus = 1
    time = { 10.min * task.attempt }
    memory = { 10.GB * task.attempt } 
    errorStrategy = { 'retry' }

    publishDir "${params.analysisDir}/${sampleID}", mode: 'copy'

    input:
    tuple val(sampleID), path(files)

    output:
    file '*multiqc*'

    script:
    """
    module load ${params.multiqc}
    multiqc -n ${sampleID}_multiqc_report.html -o ${sampleID}_multiqc_data/ .
    module unload ${params.multiqc}
    """    
}

process multiqc {
    executor = 'slurm'
    cpus = 1
    time = { 10.min * task.attempt }
    memory = { 10.GB * task.attempt } 
    errorStrategy = { 'retry' }

    publishDir "${params.analysisDir}/", mode: 'copy'

    input:
    path files

    output:
    file '*multiqc*'

    script:
    """
    module load ${params.multiqc}
    multiqc -n ${params.lake}_multiqc_report.html -o ${params.lake}_multiqc_data/ .
    module unload ${params.multiqc}
    """    
}


workflow {
    samples_ch = Channel
    .fromFilePairs("${params.rawDataDir}/*.R{1,2}.fastq.gz", flat: true)
    .map { basename, reads1, reads2 -> tuple(basename.tokenize('.').get(0), reads1, reads2) }
    //.filter { sampleID, reads1, reads -> sampleID != "<your sample ID 1>" & sampleID != "<your sample ID 2>" }

    // preprocessing
    fastqc_pre(samples_ch)
    clumpify(samples_ch) | fastp

    // second deduplication
    dedupe_ch = fastp.out[0]
    .map { sampleID, read1, read2, merged ->  tuple(sampleID, tuple(tuple("R1", read1), tuple("R2", read2), tuple("merged", merged)))} // combine fastp output into one channel
    .transpose()
    .map { sampleID, type_file -> tuple(sampleID, type_file[0], type_file[1]) }
    
    dedupe(dedupe_ch)

    // post fastqc
    fastqc_ch = dedupe.out
    .groupTuple(sort: true) // will only continue after all samples have been processed
    .map { sampleID, type, files -> tuple(sampleID, files[0], files[1], files[2]) }

    fastqc_post(fastqc_ch)

    // alignments
    databases_ch = Channel
    .fromPath(params.databases)
    .splitCsv(header: true)
    .filter { db_info -> db_info.include == "y" } // filter for databases which should be used for mapping
    .map { db_info -> tuple(db_info, file("${db_info['path']}/*.bt{2,2l}")) } // find all database files in the selected database directories
    .transpose() // make a channel entry for each file in the database directories
    .map { db_info, file -> tuple(file.getBaseName().minus(~/.\d+$/).minus('.rev'), db_info['deduplication'], file) } // remove file endings
    .groupTuple(sort: true) 
    .map { dbID, db_dedup, db_path ->  tuple(dbID, db_dedup[0], db_path)}
    .map { dbID, db_dedup, db_path -> if(dbID == "pppm.5") { tuple(dbID, "y", db_path) } else {tuple(dbID, db_dedup, db_path)}}
    .unique()

    align_ch = dedupe.out
    .filter { sampleID, type, file -> type == "merged"}
    .map { sampleID, type, file -> tuple(sampleID, file) }
    .combine(databases_ch)
    .branch { sampleID, reads, dbID, db_dedup, db_path ->
        align_dedup: db_dedup == "y"
        align: db_dedup == "n"
    }

    align(align_ch.align)
    align_dedupe(align_ch.align_dedup)

    // merging and sorting
    merge_sort_ch = align.out[0]
    .concat(align_dedupe.out[0])
    .transpose()
    .groupTuple(sort: true)

    merge_sort(merge_sort_ch) | metaDMG | post_metaDMG_LCA
    
    // post metaDMG processing
    combine_lca_ch = post_metaDMG_LCA.out
    .collect(sort: true)

    combine_lca(combine_lca_ch)
    
    // mismatch
    mismatch_ch = metaDMG.out
    .map { sampleID, directory -> directory }
    .collect(sort: true)

    mismatch(mismatch_ch)
    combine_dmg_out(mismatch_ch)

    
    // multiqc
    multiqc_all_ch = fastqc_pre.out[1]
    .concat(fastp.out[1], fastqc_post.out[1], align.out[1], align_dedupe.out[1])
    .map { sampleID, files -> files}
    .collect(sort: true)

    multiqc(multiqc_all_ch)

    multiqc_merged_ch = fastqc_post.out[2]
    .map { sampleID, files -> files}
    .collect(sort: true)

    multiqc_merged(multiqc_merged_ch)

    multiqc_sample_ch = fastqc_pre.out[1]
    .concat(fastp.out[1], fastqc_post.out[1], align.out[1], align_dedupe.out[1])
    .transpose()
    .groupTuple(sort: true)

    multiqc_sample(multiqc_sample_ch)
}