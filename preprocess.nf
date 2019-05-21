#!/usr/bin/env nextflow
/*
vim: syntax=groovy
-*- mode: groovy;-*-
========================================================================================
                         nf-toxomix preprocess
========================================================================================
 NF-toxomix Analysis Pipeline. Started 2018-02-15.
 #### Homepage / Documentation
 https://github.com/openrisknet/nf-toxomix
 #### Authors
 Evan Floden (evanfloden) <evan.floden@gmail.com> - https://github.com/evanfloden>
----------------------------------------------------------------------------------------
*/

def helpMessage() {
    log.info"""
    =========================================
     nf-toxomix preprocess v${version}
    =========================================
    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run openrisknet/nf-toxomix --sra 'ERP024544' -profile docker

    Mandatory arguments:
      --sra                         SRA/SRR Accession (default: ERP024544)
      --runtable                    Location of SRA Run Table (default: data/ERP024544/SraRunTable.txt)
      -profile                      Hardware config to use. Docker / AWS

    References                      If not specified in the configuration file or you wish to overwrite any of the references.
      --fasta                       Path to Fasta genome reference for mapping (default: Ensembl/GRCh37 on AWS S3 )

    Other options:
      --outdir                      The output directory where the results will be saved
      -name                         Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.
    """.stripIndent()
}

/*
 * SET UP CONFIGURATION VARIABLES
 */

// Pipeline version
version = '0.1.0'

// Show help emssage
params.help = false
if (params.help){
    helpMessage()
    exit 0
}

// Configurable variables
params.name = false

params.sra = "SRR390728" //"ERP024544"
params.runtable = "data/SRP020237/SraRunTable.txt" // "data/ERP024544/SraRunTable.txt"

params.multiqc_config = "$baseDir/conf/multiqc_config.yaml"
params.fasta = "ftp://ftp.ensembl.org/pub/release-96/fasta/homo_sapiens/cdna/Homo_sapiens.GRCh38.cdna.all.fa.gz"//"s3://ngi-igenomes/igenomes/Homo_sapiens/Ensembl/GRCh37/Sequence/WholeGenomeFasta/genome.fa"
params.outdir = './results'
params.email = false
params.plaintext_email = false
multiqc_config = file(params.multiqc_config)
output_docs = file("$baseDir/docs/output.md")

// Validate inputs
if ( params.fasta ){
    fasta = file(params.fasta)
    if( !fasta.exists() ) exit 1, "Fasta file not found: ${params.fasta}"
}

Channel.fromSRA(params.sra)
  .set {sra_ch}

Channel.fromPath(params.runtable)
  .set { runtable_ch}

Channel.fromPath(params.fasta)
  .set {ref_fasta}

// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if( !(workflow.runName ==~ /[a-z]+_[a-z]+/) ){
  custom_runName = workflow.runName
}

runtable_ch
  .splitCsv (header: true, sep: "\t")
  .map { it -> [it.Run, it ] }
  .join ( sra_ch )
  //.filter { record -> record[0] =~ /ERR2097731/ }
  .into { raw_reads_qc; raw_reads_trim }


  /*
   * STEP 0 - Index Reference Genome
   */
  process index {

        container 'quay.io/biocontainers/salmon:0.13.0--h86b0361_2'
        tag "$name"
        publishDir "${params.outdir}/index", mode: 'copy'

        input:
        file(fasta) from ref_fasta

        output:
        file 'index' into index_ch

        script:
        """
        salmon index --threads $task.cpus -t $fasta -i index
        """

    }


/*
 * STEP 1 - FastQC
 */
process fastqc {

      container 'biocontainers/fastqc:v0.11.5_cv4'
      tag "$name"
      publishDir "${params.outdir}/fastqc", mode: 'copy'

      input:
      set val(name), val(meta), file(reads) from raw_reads_qc

      output:
      file "*_fastqc.{zip,html}" into fastqc_results

      script:
      """
      fastqc -q $reads
      """
  }

  /*
   * STEP 2 - Trim Galore!
   */
  process trim_galore {

      container 'quay.io/biocontainers/trim-galore:0.5.0--0'
      tag "$name"
      publishDir "${params.outdir}/trim_galore", mode: 'copy'

      input:
      set val(name), val(meta), file(reads) from raw_reads_trim

      output:
      set val(name), val(meta), file("*fq.gz") into trimmed_reads
      file "*_fastqc.{zip,html}" into trimgalore_fastqc_reports

      script:
      """
      trim_galore --paired --fastqc --gzip $reads
      """
}

/*
 * STEP 2 - Quantification
 */

process quant {

    container 'quay.io/biocontainers/salmon:0.13.0--h86b0361_2'
    tag "$name"
    publishDir "${params.outdir}/quant", mode: 'copy'

    input:
    file index from index_ch
    set val(name), val(meta), file(reads) from trimmed_reads

    output:
    set val(name), val(meta), file(name) into quant_ch

    script:
    """
    salmon quant --threads $task.cpus --libType=U -i $index -1 ${reads[0]} -2 ${reads[1]} -o $name
    """
}
