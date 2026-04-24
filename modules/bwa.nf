/*
    BWA

    BWA_INDEX
    ---------
    Input : reference FASTA
    Output: tuple(fasta, [index_files])

    BWA_MEM
    -------
    Input : [ meta, [R1, R2], fasta, [index_files] ]
    Output: [ meta, sam ]

    Writes SAM not BAM. SAMTOOLS_SORT handles conversion in its own
    container so no cross-container pipe is needed.
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
    tuple val(meta), path(reads), path(fasta), path(index)

    output:
    tuple val(meta), path("*.sam"), emit: sam

    script:
    def prefix = meta.id
    def extra  = params.bwa_extra_args ?: ''
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
