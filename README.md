# nf-align-pipeline

FastQC -> Trimmomatic -> BWA -> SAMtools short-read alignment pipeline in Nextflow DSL2.

[![CI](https://github.com/yourname/nf-align-pipeline/actions/workflows/ci.yml/badge.svg)](https://github.com/yourname/nf-align-pipeline/actions/workflows/ci.yml)
![Nextflow](https://img.shields.io/badge/nextflow-%E2%89%A523.04.0-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## Pipeline steps

```
paired FASTQ
     |
     v
 FastQC (raw)            -- per-sample read QC
     |
     v
 Trimmomatic             -- adapter removal, quality trimming
     |
     v
 FastQC (trimmed)        -- confirm trimming worked
     |
     v
 BWA index (once)
     |
 BWA MEM                 -- align, embed @RG tag
     |
     v
 SAMtools sort           -- SAM -> sorted BAM
     |
     v
 SAMtools index          -- .bai index
     |
 SAMtools flagstat       -- alignment statistics
     |
     v
 MultiQC                 -- aggregated HTML report
```

### Outputs

| Directory | Contents |
|-----------|----------|
| `results/fastqc/` | HTML and ZIP reports (raw and trimmed) |
| `results/trimmomatic/` | Trimmomatic log files |
| `results/bwa_mem/` | SAM files |
| `results/samtools/` | Sorted BAM, BAI index, flagstat |
| `results/multiqc/` | `multiqc_report.html` |
| `results/pipeline_info/` | Timeline, resource report, execution DAG |

---

## Quick start

### Install Nextflow

```bash
# Requires Java 11 or later
curl -s https://get.nextflow.io | bash
sudo mv nextflow /usr/local/bin/
```

### Stub run — no tools required

```bash
git clone https://github.com/yourname/nf-align-pipeline.git
cd nf-align-pipeline
python3 test/generate_test_data.py
nextflow run main.nf -profile test -stub-run
```

### Run with Docker

```bash
nextflow run main.nf \
  -profile docker,test \
  --outdir results
```

### Run on your own data

```bash
nextflow run main.nf \
  -profile docker \
  --reads  'data/*_R{1,2}.fastq.gz' \
  --genome 'ref/genome.fa' \
  --outdir results
```

Wrap glob patterns in single quotes to prevent shell expansion.

---

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--reads` | required | Glob pattern for paired FASTQ files |
| `--genome` | required | Path to reference genome FASTA |
| `--adapters` | `assets/adapters.fa` | Adapter sequences for Trimmomatic |
| `--outdir` | `results` | Output directory |
| `--bwa_extra_args` | `-M` | Additional flags for `bwa mem` |
| `--sort_threads` | `4` | Threads for `samtools sort` |
| `--trim_leading` | `3` | LEADING quality threshold |
| `--trim_trailing` | `3` | TRAILING quality threshold |
| `--trim_slidingwindow` | `4:15` | SLIDINGWINDOW setting |
| `--trim_minlen` | `36` | MINLEN threshold |
| `--run_multiqc` | `true` | Run MultiQC at the end |

---

## Profiles

| Profile | Description |
|---------|-------------|
| `local` | Run locally without containers (tools must be in PATH) |
| `docker` | Pull containers from quay.io/biocontainers |
| `singularity` | Use Singularity images (recommended for HPC) |
| `conda` | Create per-process conda environments |
| `slurm` | Submit to a SLURM cluster |
| `test` | Use bundled synthetic test data |

Combine profiles with a comma:

```bash
nextflow run main.nf -profile singularity,slurm --reads ...
```

---

## Design notes

**Why SAM output from BWA, not BAM?**
Piping `bwa mem` into `samtools view` in the same shell command requires samtools
to be present in the BWA container. The biocontainers images are minimal and do not
include both tools. By writing SAM from `BWA_MEM` and converting in `SAMTOOLS_SORT`,
each process runs only in the container where its tool is installed. `samtools sort`
accepts SAM input natively, so no extra conversion step is needed.

**Read group tags**
`BWA_MEM` embeds a `@RG` header line (`-R`) with ID, SM, PL, LB, and PU fields.
This is required for downstream GATK tools and is good practice even when GATK is
not the next step.

**Module reuse**
The `FASTQC` process is imported twice under different aliases (`FASTQC_RAW` and
`FASTQC_TRIMMED`). This is the DSL2 pattern for running the same tool at two points
in the pipeline without duplicating any code.

**Resuming after failure**
```bash
nextflow run main.nf -resume [other params]
```
Nextflow caches completed work in the `work/` directory. Only failed or changed
tasks are re-run.

---

## Project structure

```
nf-align-pipeline/
├── main.nf
├── nextflow.config
├── assets/
│   └── adapters.fa
├── modules/
│   ├── fastqc.nf
│   ├── trimmomatic.nf
│   ├── bwa.nf
│   ├── samtools.nf
│   └── multiqc.nf
├── test/
│   ├── generate_test_data.py
│   └── data/                  (git-ignored)
└── .github/
    └── workflows/
        └── ci.yml
```

---

## License

MIT

## Results

Pipeline run on SRR062634 (100,000 reads subset, chr22 reference, GRCh38).

| Metric | Value |
|--------|-------|
| Total reads | 195,301 |
| Mapped reads | 55,273 |
| Mapping rate | 27.7% |
| Properly paired | 16.9% |

Mapping rate is expected to be low because the sample contains reads from
all chromosomes and only chr22 was used as the reference.
