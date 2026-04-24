#!/usr/bin/env nextflow

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    nf-align-pipeline
    FastQC -> Trimmomatic -> BWA -> SAMtools -> MultiQC
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

nextflow.enable.dsl = 2

include { FASTQC as FASTQC_RAW     } from './modules/fastqc'
include { FASTQC as FASTQC_TRIMMED } from './modules/fastqc'
include { TRIMMOMATIC              } from './modules/trimmomatic'
include { BWA_INDEX                } from './modules/bwa'
include { BWA_MEM                  } from './modules/bwa'
include { SAMTOOLS_SORT            } from './modules/samtools'
include { SAMTOOLS_INDEX           } from './modules/samtools'
include { SAMTOOLS_FLAGSTAT        } from './modules/samtools'
include { MULTIQC                  } from './modules/multiqc'

log.info """
    nf-align-pipeline  v${workflow.manifest.version}
    =========================================
    reads      : ${params.reads}
    genome     : ${params.genome}
    outdir     : ${params.outdir}
    """.stripIndent()

def validateParams() {
    if (!params.reads)  error "ERROR: --reads is required"
    if (!params.genome) error "ERROR: --genome is required"
}

workflow {

    validateParams()

    // ------------------------------------------------------------------
    // Input channels
    // ------------------------------------------------------------------

    // [ meta, [R1, R2] ]
    ch_reads = Channel
        .fromFilePairs(params.reads, checkIfExists: true)
        .map { id, files -> [ [id: id, single_end: false], files ] }

    // Single reference genome file
    ch_genome = Channel
        .fromPath(params.genome, checkIfExists: true)
        .first()

    // Adapter FASTA — user-supplied or bundled fallback
    ch_adapters = params.adapters
        ? Channel.fromPath(params.adapters, checkIfExists: true).first()
        : Channel.fromPath("${projectDir}/assets/adapters.fa").first()

    // ------------------------------------------------------------------
    // QC on raw reads
    // ------------------------------------------------------------------
    FASTQC_RAW(ch_reads)

    // ------------------------------------------------------------------
    // Adapter and quality trimming
    // ------------------------------------------------------------------
    TRIMMOMATIC(ch_reads, ch_adapters)

    // ------------------------------------------------------------------
    // QC on trimmed reads
    // ------------------------------------------------------------------
    FASTQC_TRIMMED(TRIMMOMATIC.out.trimmed_reads)

    // ------------------------------------------------------------------
    // Index the reference once; combine with every sample for alignment
    // ------------------------------------------------------------------
    BWA_INDEX(ch_genome)

    // BWA_INDEX emits: tuple(fasta, [index_files])
    // Combine each sample's trimmed reads with the shared index tuple
    ch_bwa_input = TRIMMOMATIC.out.trimmed_reads
        .combine(BWA_INDEX.out.index)

    // ------------------------------------------------------------------
    // Align — emits SAM (not BAM; conversion happens in SAMTOOLS_SORT
    // so that samtools only runs inside its own container)
    // ------------------------------------------------------------------
    BWA_MEM(ch_bwa_input)

    // ------------------------------------------------------------------
    // Sort SAM -> sorted BAM, then index and flagstat
    // ------------------------------------------------------------------
    SAMTOOLS_SORT(BWA_MEM.out.sam)
    SAMTOOLS_INDEX(SAMTOOLS_SORT.out.sorted_bam)
    SAMTOOLS_FLAGSTAT(SAMTOOLS_SORT.out.sorted_bam)

    // ------------------------------------------------------------------
    // Aggregate QC report
    // ------------------------------------------------------------------
    if (params.run_multiqc) {
        ch_multiqc_files = Channel.empty()
            .mix(FASTQC_RAW.out.zip)
            .mix(FASTQC_TRIMMED.out.zip)
            .mix(TRIMMOMATIC.out.log)
            .mix(SAMTOOLS_FLAGSTAT.out.flagstat)
            .collect()

        MULTIQC(ch_multiqc_files)
    }
}

workflow.onComplete {
    def status = workflow.success ? "SUCCESS" : "FAILED"
    log.info """
    Pipeline ${status}
    Completed : ${workflow.complete}
    Duration  : ${workflow.duration}
    Output    : ${params.outdir}
    """.stripIndent()
}

workflow.onError {
    log.error "Pipeline failed: ${workflow.errorMessage}"
}
