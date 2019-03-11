#!/usr/bin/env nextflow
/*
vim: syntax=groovy
-*- mode: groovy;-*-
========================================================================================
                         NF-toxomix
========================================================================================
 NF-toxomix Analysis Pipeline. Started 2018-02-15.
 #### Homepage / Documentation
 https://github.com/evanfloden/nf-toxomix
 #### Authors
 Evan Floden (evanfloden) <evan.floden@gmail.com> - https://github.com/evanfloden>
----------------------------------------------------------------------------------------
*/


def helpMessage() {
    log.info"""
    =========================================
     NF-toxomix v${version}
    =========================================
    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run skptic/NF-toxomix --reads '*_R{1,2}.fastq.gz' -profile docker

    Mandatory arguments:
      --reads                       Path to input data (must be surrounded with quotes)
      -profile                      Hardware config to use. docker / aws

    Options:
      --singleEnd                   Specifies that the input is single end reads

    References                      If not specified in the configuration file or you wish to overwrite any of the references.
      --fasta                       Path to Fasta reference

    Other options:
      --outdir                      The output directory where the results will be saved
      --email                       Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
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
params.transcriptomics_data = "ftp://ftp.ncbi.nlm.nih.gov/geo/series/GSE28nnn/GSE28878/matrix/GSE28878_series_matrix.txt.gz"

params.compound_info_excel = "$baseDir/data/Supplementary_Data_1.xls"
params.PMAtable_217_arrays = "$baseDir/data/PMAtable_217_arrays.tsv"

params.multiqc_config = "$baseDir/conf/multiqc_config.yaml"
params.reads = 'data/*_{1,2}.fq'
params.fasta = "data/l1000_transcripts.fa"
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

Channel.from(params.transcriptomics_data)
  .set {transcriptomics_data_url_ch}

Channel.fromPath(params.compound_info_excel)
  .set { compound_info_excel_ch}


// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if( !(workflow.runName ==~ /[a-z]+_[a-z]+/) ){
  custom_runName = workflow.runName
}

/*
 * Create a channel for input read files
 */
Channel
    .fromFilePairs( params.reads, size: -1 )
    .ifEmpty { exit 1, "Cannot find any reads matching: ${params.reads}\nNB: Path needs to be enclosed in quotes!\nNB: Path requires at least one * wildcard!\nIf this is single-end data, please specify --singleEnd on the command line." }
    .into { read_files_fastqc; read_files_quantify }



// Header log info
log.info "========================================="
log.info " NF-toxomix v${version}"
log.info "========================================="
def summary = [:]
summary['Run Name']     = custom_runName ?: workflow.runName
summary['Reads']        = params.reads
summary['Fasta Ref']    = params.fasta
summary['Data Type']    = params.singleEnd ? 'Single-End' : 'Paired-End'
summary['Max Memory']   = params.max_memory
summary['Max CPUs']     = params.max_cpus
summary['Max Time']     = params.max_time
summary['Output dir']   = params.outdir
summary['Working dir']  = workflow.workDir
summary['Container']    = workflow.container
if(workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Current home']   = "$HOME"
summary['Current user']   = "$USER"
summary['Current path']   = "$PWD"
summary['Script dir']     = workflow.projectDir
summary['Config Profile'] = workflow.profile
if(params.email) summary['E-mail Address'] = params.email
log.info summary.collect { k,v -> "${k.padRight(15)}: $v" }.join("\n")
log.info "========================================="


// Check that Nextflow version is up to date enough
// try / throw / catch works for NF versions < 0.25 when this was implemented
nf_required_version = '0.25.0'
try {
    if( ! nextflow.version.matches(">= $nf_required_version") ){
        throw GroovyException('Nextflow version too old')
    }
} catch (all) {
    log.error "====================================================\n" +
              "  Nextflow version $nf_required_version required! You are running v$workflow.nextflow.version.\n" +
              "  Pipeline execution will continue, but things may break.\n" +
              "  Please run `nextflow self-update` to update Nextflow.\n" +
              "============================================================"
}


/*
 * Download transcriptomics Data
 */
process get_transcriptomics_data {

    input:
        val(transcriptomics_data_url) from transcriptomics_data_url_ch

    output:
        file('transcriptomics_data.txt') into transcriptomics_data_ch
        file('transcriptomics_data_raw') into transcriptomics_data_raw_ch

    shell:
        """
        curl -X GET "${transcriptomics_data_url}" > transcriptomics_data_raw.gz
        gunzip transcriptomics_data_raw.gz
        awk -f ${baseDir}/bin/parse_transcript_data.awk  transcriptomics_data_raw|tr -d '"' > transcriptomics_data.txt
        """
}

/*
 * Process the comound info execel sheet in R with pandas
 */
process process_compound_info {

    input:
        file(compound_info_file) from compound_info_excel_ch

    output:
        file('compound_info.tsv') into compound_info_ch

    script:
    """
    #!/opt/conda/bin/python

    import pandas as pd
    print("input  is:" + str("${compound_info_file}"))
    print("output is:" + str("compound_info.tsv"))
    excel_file = pd.read_excel(io="${compound_info_file}", encoding='utf-16')
    excel_file.to_csv(path_or_buf="compound_info.tsv",  encoding='utf-8', sep="\t")
    """
  }

compound_info_ch
    .into { compound_info_ch1; compound_info_ch2 }

/*
 * Create the compound training data
 */

process training_compound_info {

      input:
      file(compound_info) from compound_info_ch1

      output:
      file("training_data_compound_info.tsv") into compound_info_training_ch

      shell:
      """

      echo -e 'compound\tgenotoxicity' > a.txt
      cut -f1,10- compound_info.tsv | tail -n +4 | head -n 34 >> a.txt
      sed -re 's/\\+\$/GTX/g; s/\\-\$/NGTX/g;  s/[[:punct:]]//g' a.txt > training_data_compound_info.tsv
  
      """
  }

process validation_compound_info {

     input:
     file(compound_info) from compound_info_ch2

     output:
     file("validation_data_compound_info.tsv") into compound_info_validation_ch

     shell:
     """
     a=\$(tempfile -d .)
     cut -f1,10- ${compound_info} |awk 'NR>41'|sed -re 's/\\+\$/GTX/g; s/\\-\$/NGTX/g;  s/[[:punct:]]//g' > \$a;
     awk 'BEGIN{{print("compound\\tgenotoxicity");}}{{print}}' \$a| sed -re 's/ppDDT\\t/DDT\\t/g; s/\\s+/\\t/g'> validation_data_compound_info.tsv
     """
}

/*
 *  Each series has different solvent, match to the correct solvent
 */

process map_sovent_to_exposure {

    input:
    file(transcriptomics_data_raw) from transcriptomics_data_raw_ch

    output:
    file("solvent2exposure.tsv") into solvent_to_exposure_ch

    shell:
    """
    a=\$(tempfile -d .)
    b=\$(tempfile -d .)
    c=\$(tempfile -d .)
    d=\$(tempfile -d .)
    e=\$(tempfile -d .)
    paste <(grep Sample_title ${transcriptomics_data_raw}|cut -f2-|tr -d '"'|tr '\\t' '\\n') <(grep Series_sample_id ${transcriptomics_data_raw} > \$a;
    cut -f2- \$a|tr -d '"'|sed -re 's/\\s*\$//'|tr ' ' '\\n')|grep 24h > \$b;
    sed -re 's/^Serie\\s*//g; s/, HepG2 exposed to\\s*/\\t/g; s/for 24h, biological rep\\s*/\\t/g' \$b > \$c;
    awk 'BEGIN{{print("series_id\\tcompound\\treplicate\\tarray_name");}}{{print}}' \$c|sed -re 's/\\s+/\\t/g' > \$d;
    sed -re 's/DEPH/DEHP/g; s/Ethyl\\t/EtAc\\t/g; s/NPD\\t/NDP\\t/g; s/Paracres\\t/pCres\\t/g; s/Phenol\\t/Ph\\t/g; s/Resor/RR/g' \$d > \$e;
    sed -re 's/2-Cl\\t/2Cl\\t/g' \$e> solvent2exposure.tsv
    """
}

solvent_to_exposure_ch
    .into{ solvent_to_exposure_ch1; solvent_to_exposure_ch2; solvent_to_exposure_ch3 }
/*
 * Create a file that stores a mapping between genotoxicity, compound and array information for validation set
 */
process map_compound_to_array_validation {

    input:
    file(validation_data_compound_info) from compound_info_validation_ch
    file(solvent2exposure) from solvent_to_exposure_ch1

    output:
    file("compound_array_genotoxicity_val.tsv") into compound_array_genotoxicity_val_ch

    shell:
    """
    echo -e "series_id\\tcompound\\treplicate\\tarray_name\\tgenotoxicity" > compound_array_genotoxicity_val.tsv;

    sed -i 's/γ//g' ${validation_data_compound_info}

    cat ${validation_data_compound_info} | LANG=en_EN sort -k1.1i,1.3i  -t \$'\\t' > validation_sorted.txt

    cat solvent2exposure.tsv | LANG=en_EN sort -bi -t \$'\\t' -k 2 > solvent_sorted.txt

    join -o 2.1,2.2,2.3,2.4,1.2 -t \$'\\t' -1 1 -2 2 validation_sorted.txt solvent_sorted.txt > a.txt

    grep -iv genotoxicity a.txt >> compound_array_genotoxicity_val.tsv;

    """
}


/*
 * Create a file that stores a mapping between genotoxicity, compound and array information for training set
 */
process map_compound_to_array_training {

    input:
    file(training_data_compound_info) from compound_info_training_ch
    file(solvent2exposure) from solvent_to_exposure_ch2

    output:
    file("compound_array_genotoxicity_train.tsv") into compound_array_genotoxicity_train_ch

    shell:
    """
    echo -e "series_id\\tcompound\\treplicate\\tarray_name\\tgenotoxicity" > compound_array_genotoxicity_train.tsv;


    cat ${training_data_compound_info} | LANG=en_EN sort -k1.1i,1.3i  -t \$'\\t' > training_sorted.txt

    cat solvent2exposure.tsv | LANG=en_EN sort -bi -t \$'\\t' -k 2 > solvent_sorted.txt

    join -o 2.1,2.2,2.3,2.4,1.2 -t \$'\\t' -1 1 -2 2 training_sorted.txt solvent_sorted.txt > a.txt

    grep -iv genotoxicity a.txt >> compound_array_genotoxicity_train.tsv;

    """
}


/*
 *  Calculate the correct log2ratio using the corresponding solvent for each replicate
 */ 

process calculate_log2_ratio {

    input:
    file (transcriptomics_data) from transcriptomics_data_ch
    file (solvent2expose) from solvent_to_exposure_ch3

    output:
    file ("log2ratio_results.txt") into log2ratio_results_ch
    file ("solvent2exposure_mapping.txt") into solvent2exposure_mapping_ch

    script:
    """
    #!/opt/conda/bin/python
    import pandas as pd

    transcr_df = pd.read_table(filepath_or_buffer="${transcriptomics_data}")
    solvent2exposure_df = pd.read_table(filepath_or_buffer = "${solvent2expose}")

    # Find corresponding solvent ids for each compound
    results_df = pd.DataFrame()
    for val in solvent2exposure_df.series_id.drop_duplicates().values:
        tmp = solvent2exposure_df.loc[solvent2exposure_df.series_id==val,:].query("compound.str.lower() in ['dmso','etoh','pbs']")
        tmp.index=range(tmp.shape[0])          
        tmp.columns = ['solvent_'+str(i) for i in tmp.columns]
        compounds = solvent2exposure_df.loc[solvent2exposure_df.series_id==val,:].query("compound.str.lower() not in ['dmso','etoh','pbs']")['compound'].drop_duplicates()
        for compound in compounds:
            tmp1 = solvent2exposure_df.loc[solvent2exposure_df.series_id==val,:].query("compound=='"+str(compound)+"'")
            tmp1.index = range(tmp1.shape[0])                
            tmp2 = pd.concat([tmp1,tmp],axis=1, join='inner')
            if results_df.shape[0] == 0:
                results_df = tmp2
            else:
                results_df = results_df.append(tmp2)
    results_df.to_csv(path_or_buf=str("solvent2exposure_mapping.txt"), sep="\\t", index=False)

    # Calculate log2ratio
    log2ratio_df = pd.DataFrame()
    for compound in results_df['compound'].drop_duplicates().values:
        for replicate in results_df[results_df['compound']==compound].replicate:
            compound_array = results_df[results_df['compound']==compound].query('replicate=='+str(replicate)).array_name.values[0]
            solvent_array  = results_df[results_df['compound']==compound].query('replicate=='+str(replicate)).solvent_array_name.values[0]
            tmp3 = transcr_df.loc[:,compound_array] - transcr_df.loc[:,solvent_array]
            tmp3.index = transcr_df.index
            tmp3.columns = [compound_array]
            if log2ratio_df.shape[0] == 0:
                log2ratio_df = tmp3
                log2ratio_df.columns = tmp3.columns
                log2ratio_df.index = tmp3.index
            else:
                column_names = list(log2ratio_df.columns)
                column_names.append(compound_array)
                log2ratio_df = pd.concat([log2ratio_df,tmp3],axis=1)
                log2ratio_df.columns = column_names

    column_names = list(log2ratio_df.columns)
    column_names.insert(0,'ID_REF')
    log2ratio_df = pd.concat([transcr_df['ID_REF'],log2ratio_df], axis=1)
    log2ratio_df.columns = column_names
    log2ratio_df.to_csv(path_or_buf=str("log2ratio_results.txt"), sep="\\t", index=False)
    """
 
}


process filter_absent_genes {
    input:
        file PMAtable_217_arrays from Channel.fromPath(params.PMAtable_217_arrays)
        file log2ratio_results from log2ratio_results_ch
        file solvent2exposure_mapping from solvent2exposure_mapping_ch

    output:
        file "filtered_pma_table" into filtered_pma_table_ch
        file "filtered_log2ratio" into filtered_log2ratio_ch

    shell:
        """
        /opt/conda/bin/python ${baseDir}/bin/presence_absence_pma_table.py ${PMAtable_217_arrays} \
            ${solvent2exposure_mapping} \
            "filtered_pma_table" \
            ${log2ratio_results} \
            "filtered_log2ratio"
        """
}


filtered_log2ratio_ch
  .into { filtered_log2ratio_ch_1; filtered_log2ratio_ch_2 } 

process create_training_data {

    // Create a training data, where 2nd row contains genotoxicity information

    input:
        file filtered_log2ratio from filtered_log2ratio_ch_1
        file compound_array_genotoxicity_train from compound_array_genotoxicity_train_ch

    output:
        file "training_data.tsv" into training_data_ch

    script:
    """
    #!/opt/conda/bin/python
    import pandas as pd
    log2ratio_df = pd.read_table(filepath_or_buffer="${filtered_log2ratio}")
    comp_arr_gtx_df = pd.read_table(filepath_or_buffer="${compound_array_genotoxicity_train}")
    arrays_ids = log2ratio_df.columns.values
    gtx_info = {}
    gtx_array_names = comp_arr_gtx_df.loc[:,'array_name'].values
    for arr in arrays_ids[1:]:
        if not arr in gtx_array_names: continue
        print(arr)
        tmp = comp_arr_gtx_df.loc[comp_arr_gtx_df['array_name']==arr,'genotoxicity']
        if len(tmp)==1:
            gtx_info[arr]= tmp.values[0]
    gtx_info_cols = list(gtx_info.keys())
    gtx_info_cols.sort()
    gtx_info_classes = [gtx_info[i] for i in gtx_info_cols]
    gtx_info_cols.insert(0,arrays_ids[0])
    gtx_info_classes.insert(0,"class")
    training_data_df = pd.DataFrame([gtx_info_classes],columns=gtx_info_cols)
    training_data_df = training_data_df.append(log2ratio_df.loc[:,gtx_info_cols])
        
    # For later reading in R, do not give a label for the first column
    col_names = list(training_data_df.columns[1:])
    col_names.insert(0,"")
    training_data_df.to_csv(path_or_buf=str("training_data.tsv"),sep="\\t", index=False, header=col_names)
    """
}


process create_validation_data {

    // Create validation data, where 2nd row contains gen 
    input:
        file filtered_log2ratio from filtered_log2ratio_ch_2
        file compound_array_genotoxicity_val from compound_array_genotoxicity_val_ch

    output:
        file "validation_data.tsv" into validation_data_ch

    script:
    """
    #!/opt/conda/bin/python
    import pandas as pd
    log2ratio_df = pd.read_table(filepath_or_buffer="${filtered_log2ratio}")
    comp_arr_gtx_df = pd.read_table(filepath_or_buffer="${compound_array_genotoxicity_val}")
    arrays_ids = log2ratio_df.columns.values
    gtx_info = {}
    gtx_array_names = comp_arr_gtx_df.loc[:,'array_name'].values
    for arr in arrays_ids[1:]:
        if not arr in gtx_array_names: continue
        print(arr)
        tmp = comp_arr_gtx_df.loc[comp_arr_gtx_df['array_name']==arr,'genotoxicity']
        if len(tmp)==1:
            gtx_info[arr]= tmp.values[0]
    gtx_info_cols = list(gtx_info.keys())
    gtx_info_cols.sort()
    gtx_info_classes = [gtx_info[i] for i in gtx_info_cols]
    gtx_info_cols.insert(0,arrays_ids[0])
    gtx_info_classes.insert(0,"class")
    val_data_df = pd.DataFrame([gtx_info_classes],columns=gtx_info_cols)
    val_data_df = val_data_df.append(log2ratio_df.loc[:,gtx_info_cols])
    # For later reading in R, do not give a label for the first column
    col_names = list(val_data_df.columns[1:])
    col_names.insert(0,"")

    val_data_df.to_csv(path_or_buf=str("validation_data.tsv"),sep="\\t", index=False, header=col_names)
    """
}
