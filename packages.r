## This file is part of Codeface. Codeface is free software: you can
## redistribute it and/or modify it under the terms of the GNU General Public
## License as published by the Free Software Foundation, version 2.
##
## This program is distributed in the hope that it will be useful, but WITHOUT
## ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
## FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
## details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
##
## Copyright 2014 by Roger Meier <roger@bufferoverflow.ch>
## Copyright 2015 by Andreas Ringlstetter <andreas.ringlstetter@gmail.com>
## Copyright 2015 by Wolfgang Mauerer <wolfgang.mauerer@oth-regensburg.de>
## Copyright 2015 by Claus Hunsen <hunsen@fim.uni-passau.de>
## All Rights Reserved.

filter.installed.packages <- function(packageList)  {
    if("-f" %in% commandArgs(trailingOnly = TRUE)) {
        return(packageList)
    } else {
        return(packageList[which(packageList %in% installed.packages()[,1] == FALSE)])
    }
}

## Remove package from all libraries (i.e., .libPaths())
remove.installed.packages <- function(pack) {
    for (path in .libPaths()) {
        # try to remove package (hard stop() otherwise, if not existing)
        tryCatch({
            remove.packages(pack, path)
            print(paste("removed previously installed package", pack))
        }, error = function(e) {
            # silently ignore errors (the reason would be that a package
            # is not installed)
        })
    }
}

## (re-)install a package from github
reinstall.package.from.github <- function(package, url) {

    ## if package is installed, remove it completely from all libraries
    p <- filter.installed.packages(c(package))
    if(length(p) == 0) {
        remove.installed.packages(package)
    }

    ## Re-install packages
    devtools::install_github(url, quiet=T)
}

library(parallel)
num.cores <- detectCores(logical=TRUE)
if (is.na(num.cores)) {
    num.cores <- 1
}

## install potentially unresolvable dependencies
if (!requireNamespace("devtools", quietly=TRUE)) {
    install.packages("devtools")
}
library(devtools)

pinned.packages <- c(
    BH="https://cran.r-project.org/src/contrib/Archive/BH/BH_1.75.0-0.tar.gz",
    slam="https://cran.r-project.org/src/contrib/Archive/slam/slam_0.1-40.tar.gz",
    arules="https://cran.r-project.org/src/contrib/Archive/arules/arules_1.5-0.tar.gz",
    proxy="https://cran.r-project.org/src/contrib/Archive/proxy/proxy_0.4-16.tar.gz",
    logging="https://cran.r-project.org/src/contrib/Archive/logging/logging_0.8-104.tar.gz",
    rjson="https://cran.r-project.org/src/contrib/Archive/rjson/rjson_0.2.20.tar.gz"
)
pinned.versions <- c(BH="1.75.0-0", slam="0.1-40", arules="1.5-0",
                     proxy="0.4-16", logging="0.8-104", rjson="0.2.20")

install.proxy.0.4.16 <- function(url) {
    workdir <- tempfile("proxy-0.4-16-")
    dir.create(workdir)
    on.exit(unlink(workdir, recursive=TRUE), add=TRUE)
    archive <- file.path(workdir, "proxy.tar.gz")
    download.file(url, archive, mode="wb", quiet=TRUE)
    untar(archive, exdir=workdir)
    registry <- file.path(workdir, "proxy", "R", "registry.R")
    code <- readLines(registry)
    old <- "        if (!is.na(type) && !(is.character(type)))"
    new <- "        if (!any(is.na(type)) && !(is.character(type)))"
    matches <- which(code == old)
    if (length(matches) != 1L) {
        stop("proxy 0.4-16 compatibility patch no longer applies cleanly")
    }
    code[matches] <- new
    writeLines(code, registry)
    devtools::install_local(file.path(workdir, "proxy"), dependencies=FALSE,
                            upgrade="never", force=TRUE, quiet=TRUE)
}

install.pinned.packages <- function() {
    for (package in names(pinned.packages)) {
        actual <- tryCatch(packageDescription(package)$Version,
                           error=function(e) NA_character_)
        if (!is.na(actual) && actual == pinned.versions[[package]]) {
            next
        }
        if (package == "proxy") {
            install.proxy.0.4.16(pinned.packages[[package]])
        } else {
            devtools::install_url(pinned.packages[[package]], dependencies=FALSE,
                                  upgrade="never", force=TRUE, quiet=FALSE)
        }
        actual <- tryCatch(packageDescription(package)$Version,
                           error=function(e) NA_character_)
        if (is.na(actual) || actual != pinned.versions[[package]]) {
            stop(sprintf("failed to install %s %s (found %s)", package,
                         pinned.versions[[package]], actual))
        }
    }
}

# Some of these versions are needed while resolving the remaining packages.
# Install them again at the end because CRAN/Bioconductor dependency handling
# may otherwise replace them with current releases.
install.pinned.packages()
#devtools::install_url("https://cran.r-project.org/src/contrib/Archive/tm/tm_0.7-1.tar.gz")
#devtools::install_url("https://cran.r-project.org/src/contrib/Archive/markovchain/markovchain_0.6.9.11.tar.gz")
devtools::install_github("nathan-russell/hashmap")

## install from BioConductor
p <- filter.installed.packages(c("BiRewire", "BiocGenerics", "graph"))
if(length(p) > 0) {

    #source("http://bioconductor.org/biocLite.R")
    #biocLite(p)
    install.packages("BiocManager")
    BiocManager::install(p, update=FALSE, ask=FALSE)
}

## install from CRAN
p <- filter.installed.packages(c("statnet", "tm", "optparse", "arules", "data.table", "plyr",
                                 "igraph", "zoo", "xts", "lubridate", "xtable", "ggplot2",
                                 "reshape", "wordnet", "stringr", "yaml", "ineq",
                                 "scales", "gridExtra", "RMySQL", "svglite",
                                 "RCurl", "mgcv", "shiny", "dtw", "httpuv", "devtools",
                                 "corrgram", "logging", "png", "rjson", "lsa", "RJSONIO",
                                 "GGally", "corrplot", "psych", "markovchain", "hashmap"))
if(length(p) > 0) {
    install.packages(p, dependencies=T, verbose=F, quiet=F, Ncpus=num.cores)
}


## Install following packages from different sources
## and update existing installations, if needed
reinstall.package.from.github("tm.plugin.mail", "bockthom/tm-plugin-mail/pkg")
reinstall.package.from.github("snatm", "wolfgangmauerer/snatm/pkg")
reinstall.package.from.github("shinyGridster", "wch/shiny-gridster")
reinstall.package.from.github("shinybootstrap2", "rstudio/shinybootstrap2")

## Bioconductor packages
#source("https://bioconductor.org/biocLite.R")
#biocLite("Rgraphviz")
BiocManager::install("Rgraphviz", update=FALSE, ask=FALSE)

## Reassert Codeface's exact versions after every dependency has been installed.
install.pinned.packages()
