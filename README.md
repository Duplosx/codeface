# Installing and using Codeface

## Contents

1. [Docker Image](#1-docker-image)
2. [Run docker container](#2-run-docker-container)
3. [Configure Database](#3-configure-database)
4. [Run Codeface analysis](#4-run-codeface-analysis)
5. [Troubleshooting / Q&A](#5-troubleshooting--qa)

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
git clone https://github.com/apache/zeppelin.git \
  /workspace/repos/zeppelin
```

### 4.2 Create configuration file (/workspace/zeppelin_proximity.conf) for the corresponding repository.

```yaml
project: zeppelin_proximity
repo: zeppelin              # Source: git://git.apache.org/zeppelin.git
description: Apache Zeppelin
revisions: [ ]
rcs: [ ]
tagging: proximity
windowSize: 3

mailinglists:
    - {name: apache-zeppelin-dev, type: dev, source: apache}

issueTrackerType: jira
issueTrackerProject: ZEPPELIN
issueTrackerURL: https://issues.apache.org/jira
issueTrackerUser: codeface
issueTrackerPassword: codeface

# Conway analysis settings
artifactType: file
dependencyType: co-change
qualityType: defect
communicationType: jira
```

### 4.3 Check `~/run.conf`
`run/run.sh` reads `~/run.conf`. The default `~/run.conf` configuration (used for local database) is:

```bash
CFCONF="/workspace/codeface/codeface.conf"
CSCONF="/workspace/zeppelin_proximity.conf"
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



## 5. Troubleshooting / Q&A

#### TODO
