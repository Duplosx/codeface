## Contents

1. [Installing and using Codeface (Docker Guide) **Recommended**](#installing-and-using-codeface-docker-guide-recommended)
    
    - [Docker Image](#1-docker-image)
    - [Run docker container](#2-run-docker-container)
    - [Configure Database](#3-configure-database)
    - [Run Codeface analysis](#4-run-codeface-analysis)

2. [Installing and using Codeface (Manual Guide)](#installing-and-using-codeface-manual-guide)

    - [Manual Installation](#1-manual-installation)

3. [Available arguments](#available-arguments)

4. [Troubleshooting / Q&A](#troubleshooting--qa)



# Installing and using Codeface (Docker Guide) **Recommended**
Run Codeface in a reproducible containerized environment.

## 1. Docker Image

### 1.1 Build from scratch
Build from the repository root:

```sh
docker build -t codeface:image .
```


### 1.2 Pull the existing image from Docker Hub

Download the public image:
```sh
sudo docker pull duplosx75/codeface:image
```


## 2. Run Docker Container

Then use this command from ~/codeface-project, mounting the current directory

```sh
sudo docker run --rm -it \
  --network host \
  -v "$PWD:/workspace" \
  -w /workspace/codeface \
  --entrypoint /bin/bash \
  codeface:image -i
```

## 3. Configure Database

### 3.1 Configure local database 

Inside the container, run:
```sh
CODEFACE_INSTALL_R_PACKAGES=0   bash install/install_codeface.sh --database local
```


### 3.2 Configure external database 
Create database credentials for database:
A working conf is already present in the repository - codeface/codeface.conf. If needed, change the following keys to run codeface using an external database.
```yaml
---
# Database access information
dbhost: <HOST>
dbuser: <USER>
dbpwd: <PASSWORD>
dbname: <NAME>


# PersonService Settings
idServicePort: 8181
idServiceHostname: localhost

# Java BugExtractor Settings
sleepTime: 1000
# Specify proxyHost when no direct http connections are possible
#proxyHost: proxy.host.tld
proxyPort: 83
```

Inside the container, run:
```bash
bash install/verify_codeface.sh \
  --db-config /workspace/external_db.conf
```

## 4. Run Codeface analysis

### 4.1 Clone the repository you want to analyse.
Inside the container, run:
```sh
mkdir -p /workspace/repos
git clone https://git.busybox.net/busybox/ \
  /workspace/repos/busybox
```

### 4.2 Create configuration file (/workspace/busybox_feature.conf) for the corresponding repository.

```yaml
# Repository: git://busybox.net/busybox.git
---
project: busybox_feature
repo: busybox # Relative to git-dir as specified on the command line
description: busybox

mailinglists:
    -   name: gmane.linux.busybox
        type: dev
        source: gmane

# date of first release: Tue Oct 5 16:24:54 1999 +0000
# 1999-10-05
revisions: []


tagging: feature
```

### 4.3 Check `~/run.conf`
`run/run.sh` reads `~/run.conf`. The default `~/run.conf` configuration (used for local database) is:

```bash
CFCONF="/workspace/codeface/codeface.conf"
CSCONF="/workspace/busybox_feature.conf"
REPOS="/workspace/repos/"
MAILINGLISTS="/workspace/mailinglists"
RESULTS="/workspace/results"
LOGS="/workspace/logs"
TITAN="/workspace/codeface/titan"
```

When using an external database, set `CFCONF` to the external configuration
used during installation, for example:

```bash
CFCONF="/workspace/external_db.conf"
```

### 4.4 Execute the Codeface workflow

Inside the container, run:
```sh
mkdir -p /workspace/logs /workspace/results
cd /workspace/codeface
bash run/run.sh run
```




# Installing and using Codeface (Manual Guide)
Install Codeface and its dependencies directly on a Linux system.

## 1. Manual Installation
```sh
cd codeface
bash install/install_codeface.sh --database local
source .venv/bin/activate
```

or for external database, run:

```sh
cd codeface
bash install/install_codeface.sh --database external --db-config /path/to/external_db.conf.conf
source .venv/bin/activate
```

Then, follow Step [3](#3-configure-database) & [4](#4-run-codeface-analysis), as shown in the Docker Guide.

**Note**: The paths specified in Step [3](#3-configure-database) & [4](#4-run-codeface-analysis) are tailored to the Docker environment and must be adjusted to reflect the directory structure of a manual installation. 

# Available arguments

For repository analysis, with the ID service running:

```sh
codeface -j 4 run -c codeface.conf -p /workspace/busybox_feature.conf \
  --incremental /workspace/results /workspace/repos
```

The final two arguments are the results directory and the parent directory
containing the Git repositories.

| Argument | Purpose |
| --- | --- |
| `-j N` | Parallel cores (default: `1`); place before `run`. |
| `-c FILE` | Global configuration (default: `codeface.conf`). |
| `-p FILE` | Required project configuration. |
| `--incremental` | Skip completed, unchanged ranges. |
| `--no-report` | Skip LaTeX reports and dot compilation. |
| `--all-files` | Include files beyond the default source-code extensions. |
| `--skip-identity-merging` | Keep distinct name/email pairs separate. |
| `--recreate` | Delete existing project data in the database and rebuild. |

For all options, use `codeface --help` or `codeface <command> --help`.
Commands include `run`, `ml`, `conway`, `dynamic`, and `test`.

`bash run/run.sh <command>` supports `run`, `ml`, and `conway`, and manages the
ID service. It does not forward extra options; edit its CLI invocation to
change them.

# Troubleshooting / Q&A

#### TODO
