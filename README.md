
<img src="https://raw.githubusercontent.com/skptic/nf-toxomix/master/assets/orn_logo.png" width="400">


# nf-toxomix
A series of workflows for toxicology predictions based on transcriptomic profiles.

This repository acts a pilot workflow as part of the [OpenRiskNet](https://openrisknet.org/) project with the goal to
incorporate genomic data into the OpenRiskNet infrastructure.

[![Build Status](https://travis-ci.org/skptic/NF-toxomix.svg?branch=master)](https://travis-ci.org/skptic/NF-toxomix)
[![Nextflow](https://img.shields.io/badge/nextflow-%E2%89%A50.24.0-brightgreen.svg)](https://www.nextflow.io/)


## Introduction
nf-toxomix: A workflow for toxicology predictions based on transcriptomic profiles

The pipeline is built using [Nextflow](https://www.nextflow.io), a workflow tool to run tasks across multiple compute
infrastructures in a very portable manner. It comes with docker / singularity containers making installation trivial
and results highly reproducible.

### Aims

This work forms part of the OpenRiskNet which is a 3 year project funded by the European Commission within Horizon2020
EINFRA-22-2016 Programme. The primary aim was to showcase examples of where external computational and data resources
can be harnessed from within the virtual research environment (VRE).

As part of Task 2.8, we embarked on the goal of interconnecting the VRE with external infrastructures, both external
data and compute resources. The workflow is split into two parts with the first pre-procesing steps demonstrating
how external data can can be sourced from the Sequence Read Archive and processed on public cloud resources.
The second part demonstrates how a transcriptomic analysis workflow can be containerised and run on any infrastructure.


### Setting up Nextflow within the OpenRiskNet VRE

The OpenRiskNet VRE is based on the [OpenShift](https://www.openshift.com/) from Red Hat. OpenShift is a managed
container platform based on Kubernetes. More information about OpenShift within the VRE can be
found [here](https://github.com/OpenRiskNet/home/tree/master/openshift).

To connect Nextflow into the reference VRE, we created a project (equivalent of a Kubernetes namespace) called “nextflow”.
Within this project, a cluster was provisioned where Nextflow pipelines can be executed. Nodes are dedicated to executing Nextflow
by means of labels and a default node selector for the nextflow project. Additionally, consolidated logging, metrics and prometheus
were installed to allow monitoring. Five persistent volumes (PVs) named nf-pv-000{1-5} and corresponding persistent volumes claims
(PVCs) nf-pvc-000{1-5} were created to enable individual tasks (pods) to share data via a NFS from the nf-infra node. Input/output
for a workflow data can be sent over ssh to the nf-infra node in the /exports-nf/pv-000{1-5} directories. This /exports-nf directory
is backed by a 300GB cinder volume, with each PVC being limited to 100GB.

The complete OpenShift recipe can be found on the OpenRiskNet repository at:
https://github.com/OpenRiskNet/home/tree/master/openshift/recipes/nextflow-cluster


### Preprocessing transcriptomic data on the public cloud from the VRE

This demonstration looks at how to preprocess external transcriptomic data from public resources. The steps will include
downloading the data from the NCBI to a public cloud (an S3 bucket), trimming and mapping reads using AWS Batch with
EC2 Spot instances, and finally returning the read counts for each sample. Note that this is all orchestrated from the VRE
but the computation is performed on public cloud resources.


### Transciptomic-based toxicity prediction

This part of the demonstration is derived work by from Juma Bayjan at Maastricht University which in turn aimed to reproduce
the article "A transcriptomics-based in vitro assay for predicting chemical genotoxicity in vivo", by C.Magkoufopoulou et. al.

This workflow focuses on training the genotoxicity model using a subset of transcriptomic read count data and then testing the
predictions on another subset of this data.


## Documentation
The NF-toxomix pipeline comes with documentation about the pipeline, found in the `docs/` directory:

1. [Installation](docs/installation.md)
2. Pipeline configuration
    * [Local installation](docs/configuration/local.md)
    * [Adding your own system](docs/configuration/adding_your_own.md)
3. [Running the pipeline](docs/usage.md)
4. [Output and how to interpret the results](docs/output.md)
5. [Troubleshooting](docs/troubleshooting.md)

### Credits
This work was written by Evan Floden ([evanfloden](https://github.com/evanfloden)) at [Center for Genomic Regulation (CRG)](http://www.crg.eu) with
support from the OpenRiskNet consortium

### About
OpenRiskNet is a 3 year project funded by the European Commission within Horizon2020 EINFRA-22-2016 Programme (Grant Agreement 731075; start date 1 December 2016).
<img src="https://raw.githubusercontent.com/skptic/nf-toxomix/master/assets/EU-logo.png" width="400">
