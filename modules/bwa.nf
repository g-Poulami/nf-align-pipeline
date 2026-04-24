/*
    BWA

    BWA_INDEX
    ---------
    Input : reference FASTA
    Output: tuple(fasta, [index_files])
            The FASTA is passed through so downstream processes can
            reference it alongside its index files in a single tuple.

    BWA_MEM
    -------
    Input : [ meta, [R1, R2], fasta, [index_files] ]
    Output: [ meta, sam ]

    Important: this process writes plain SAM, not BAM.
    Piping `bwa mem` directly into `samtools view` would require samtools
    to be installed in the BWA container, which it is not. Keeping the
    output as SAM means SAMTOOLS_SORT (running in its own container) handles
    the format conversion and sorting in a single operation.
*/

process BWA_INDEX {
    tag        "${fasta.baseName}"
    label      'process_high'
    publishDir "${params.outdir}/bwa_index", mode: 'copy'

    input:
    path fasta

    output:
    tuple path(fasta), path("${fasta}.*"), emit: index

    script:
    """
    bwa index ${fasta}
    """

    stub:
    """
    touch ${fasta}.amb ${fasta}.ann ${fasta}.bwt ${fasta}.pac ${fasta}.sa
    """
}

process BWA_MEM {
    tag        "${meta.id}"
    label      'process_high'
    publishDir "${params.outdir}/bwa_mem/${meta.id}", mode: 'copy'

    input:
    // Produced by: TRIMMOMATIC.out.trimmed_reads .combine( BWA_INDEX.out.index )
    tuple val(meta), path(reads), path(fasta), path(index)

    output:
    tuple val(meta), path("*.sam"), emit: sam

    script:
    def prefix = meta.id
    def extra  = params.bwa_extra_args ?: ''
    // Read group — required for downstream GATK compatibility
    def rg     = "@RG\\tID:${prefix}\\tSM:${prefix}\\tPL:ILLUMINA\\tLB:${prefix}\\tPU:${prefix}"
    """
    bwa mem \\
        -t ${task.cpus} \\
        -R "${rg}" \\
        ${extra} \\
        ${fasta} \\
        ${reads[0]} ${reads[1]} \\
        > ${prefix}.sam
    """

    stub:
    """
    touch ${meta.id}.sam
    """
}
