# Dockerfile ##################################################################
#
# What:      The moves-anywhere v3 image (release 3.1.0; 3.0.0 and v2 are the previous images).
# Does:      Builds on ubuntu:20.04: MariaDB, Java 11, Python 3 and R with pinned packages; fetches
#            EPA MOVES at MOVES_COMMIT and loads its default database in one layer (setupdb.sh);
#            links MOVES's bundled Ant (3.1.0); compiles MOVES (Go: a current go.dev release that lives
#            only inside that one step, 3.1.0);
#            installs rclone from its official release (3.1.0); copies in scripts/ and installs catr.
# Called by: buildme_cloud.sh (docker buildx build). Checked by tests/test_dockerfile_static.sh.
# Reads:     setenv.sh, my.cnf, setupdb.sh, scripts/ (the build context)
# Writes:    the image
# Exits:     n/a (a failed RUN stops the build)
###############################################################################

FROM ubuntu:20.04

# Build arguments
# MOVES_COMMIT: the exact USEPA/EPA_MOVES_Model commit baked into the image (the one v2 shipped).
# Debug data (MOVES keepDebugData) is a RUNTIME switch (parameters.json "debug": true); see task_launch_moves.sh.
ARG MOVES_COMMIT=2c4cd1ab31b53bc9731492544fcbd0a6e47b970a
# GIT_REVISION (the moves_anywhere commit) is declared just before the labels at the end, so a new commit
# does not invalidate the build cache of every step (3.1.0).

# Create directory
RUN mkdir cat

# Create and change to this directory
WORKDIR cat

# Set environment variable so apt-get runs without interactive dialogue
ARG DEBIAN_FRONTEND=noninteractive

# Install dependencies
# Go is not installed here: the compile step below fetches it and removes it again (3.1.0).
# rclone is not installed from Ubuntu (its 1.50.2 was built with Go 1.13.8): see the rclone step below (3.1.0).
# Ant is not installed from Ubuntu (1.10.7): MOVES's own bundled Ant is used, see the Ant step below (3.1.0).
RUN apt-get update && apt-get install -y \
    mariadb-server \
    openjdk-11-jdk \
    git \
    unzip \
    sudo \
    libmariadb-dev \
    libxml2-dev \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Upgrade R
# Install dependencies
# python3: the run scripts use it (standard library only). lsb-release: the R repository line below.
# software-properties-common is not installed (3.1.0): nothing used it, and it brought in the system
# Python packages requests, urllib3 and certifi.
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    lsb-release \
    dirmngr \
    gnupg \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Add R repository and install the latest R version
RUN curl -fsSL https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | gpg --dearmor -o /usr/share/keyrings/cran-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cran-archive-keyring.gpg] https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/" | tee /etc/apt/sources.list.d/cran.list && \
    apt-get update && \
    apt-get install -y r-base && \
    rm -rf /var/lib/apt/lists/*

# Install new R dependencies
# remotes is pinned to the version v2 shipped (2.5.0): the current CRAN release
# if it matches, otherwise the CRAN archive.
RUN R -e "tryCatch(install.packages('remotes', repos = 'http://cran.us.r-project.org'), error = function(e) NULL); if (as.character(packageVersion('remotes')) != '2.5.0') install.packages('https://cran.r-project.org/src/contrib/Archive/remotes/remotes_2.5.0.tar.gz', repos = NULL, type = 'source'); stopifnot(as.character(packageVersion('remotes')) == '2.5.0')"

# Install More R Packages
RUN R -e "remotes::install_version('dplyr', version = '1.1.0', repos = 'http://cran.us.r-project.org')"
RUN R -e "remotes::install_version('readr', version = '2.1.4', repos = 'http://cran.us.r-project.org')"
RUN R -e "remotes::install_version('tidyr', version = '1.3.0', repos = 'http://cran.us.r-project.org')"
RUN R -e "remotes::install_version('purrr', version = '1.0.1', repos = 'http://cran.us.r-project.org')"
RUN R -e "remotes::install_version('lubridate', version = '1.9.2', repos = 'http://cran.us.r-project.org')"
RUN R -e "remotes::install_version('stringr', version = '1.5.0', repos = 'http://cran.us.r-project.org')"
RUN R -e "remotes::install_version('vroom', version = '1.6.3', repos = 'http://cran.us.r-project.org')"

RUN R -e "remotes::install_version('xml2', version = '1.3.6', repos = 'http://cran.us.r-project.org')"
RUN R -e "remotes::install_version('jsonlite', version = '1.8.9', repos = 'http://cran.us.r-project.org')"

RUN R -e "remotes::install_version('dbplyr', version = '2.3.2', repos = 'http://cran.us.r-project.org')"
# plogr (RMariaDB's build dependency) left CRAN; install it from the archive first, then pin RMariaDB to v2's version and fail loudly.
RUN R -e "remotes::install_version('plogr', version = '0.2.0', repos = 'http://cran.us.r-project.org'); remotes::install_version('RMariaDB', version = '1.3.1', repos = 'http://cran.us.r-project.org'); library(RMariaDB)"


# Try again for core ones (RMySQL pinned to the v2 version)
RUN R -e "remotes::install_version('RMySQL', version = '0.11.1', repos = 'http://cran.us.r-project.org'); packageVersion('RMySQL')"

# Install dependencies for httr
RUN apt-get update && apt-get install -y \
    libssl-dev \
    libcurl4-openssl-dev \
    wget \
    && rm -rf /var/lib/apt/lists/*

# httr is used by catr (pinned to the v2 version)
RUN R -e "remotes::install_version('httr', version = '1.4.7', repos = 'http://cran.us.r-project.org'); packageVersion('httr');"


# Staged copies, used by the single big RUN below (setenv.sh goes into the MOVES tree after checkout).
COPY setenv.sh /cat/stage/setenv.sh
# Setting mysql/mariadb configurations based on MOVES repository README
COPY my.cnf /etc/my.cnf
COPY setupdb.sh /cat/setupdb.sh

# ONE layer for the MOVES tree (about 1 GB): fetch ONLY MOVES_COMMIT (no history, no .git kept),
# unzip the default-database dump, give mysql ownership and group permissions on /cat, load the
# databases with setupdb.sh, then delete the dump (.sql and .zip) in the same RUN so no layer keeps it.
# MOVES_COMMIT is also an ENV so the run manifest can report it without .git (task_pack.sh).
ENV MOVES_COMMIT=$MOVES_COMMIT
SHELL ["/bin/bash", "-c"]
RUN set -e &&     mkdir -p EPA_MOVES_Model && cd EPA_MOVES_Model &&     git init -q &&     git remote add origin https://github.com/USEPA/EPA_MOVES_Model.git &&     git fetch -q --depth 1 origin "$MOVES_COMMIT" &&     git checkout -q FETCH_HEAD &&     test "$(git rev-parse HEAD)" = "$MOVES_COMMIT" &&     rm -rf .git && cd /cat &&     mv -f /cat/stage/setenv.sh /cat/EPA_MOVES_Model/setenv.sh && rmdir /cat/stage &&     unzip -q EPA_MOVES_Model/database/Setup/movesdb20241112.zip -d EPA_MOVES_Model/database/Setup &&     chown -R mysql:mysql /cat &&     chmod -R 6777 /cat &&     chmod +x /cat/setupdb.sh &&     /cat/setupdb.sh &&     rm -f EPA_MOVES_Model/database/Setup/movesdb20241112.sql EPA_MOVES_Model/database/Setup/movesdb20241112.zip

# Ant: the Apache Ant that EPA bundles in the MOVES tree (ant/, 1.10.15), the one MOVES's setenv.sh puts on
# PATH, linked into /usr/local/bin so the compile below and the run scripts (`sudo -u mysql ant run`; sudo's
# secure_path searches /usr/local/bin first) use it. 3.0.0 used Ubuntu's ant 1.10.7. EPA's files are unchanged.
RUN ln -s /cat/EPA_MOVES_Model/ant/bin/ant /usr/local/bin/ant && \
    ant -version | grep -q "Apache Ant(TM) version 1.10.15 "

# Compile MOVES (Java and Go) at build time, so no run compiles anything.
# D29: keepDebugData becomes a JVM property, default false, so a RUN can opt in with
# JAVA_TOOL_OPTIONS=-Dmoves.keepDebugData=true (task_launch_moves.sh sets it when parameters.json has "debug": true).
# 3.1.0: EPA's Go source (calc/ and generators/, unchanged) is compiled with a current Go release from
# go.dev, checked against its published SHA-256, used by `ant go64` and deleted in this same RUN with its
# build cache, so no layer keeps a Go toolchain. MOVES does not call `go` at run time. 3.0.0 compiled the
# same source with Ubuntu's golang-go (Go 1.13.8). GOAMD64=v1 (the default) keeps plain x86-64 floating
# point, no fused multiply-add. 3.1.0 shipped only after its outputs matched 3.0.0 exactly.
ARG GO_VERSION=1.27.4
ARG GO_SHA256=7226736c2339719cda28fbf3a54d71aa63bcefe376e98cef00034268dab24840
RUN set -e && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tgz && \
    echo "${GO_SHA256}  /tmp/go.tgz" | sha256sum -c - && \
    tar -C /tmp -xzf /tmp/go.tgz && rm -f /tmp/go.tgz && \
    export PATH="/tmp/go/bin:$PATH" GOTOOLCHAIN=local GOAMD64=v1 GOCACHE=/tmp/gocache GOPATH=/tmp/gopath && \
    test "$(go env GOVERSION)" = "go${GO_VERSION}" && \
    cd /cat/EPA_MOVES_Model && \
    sed -i 's/static final boolean keepDebugData = false;/static final boolean keepDebugData = Boolean.getBoolean("moves.keepDebugData");/' gov/epa/otaq/moves/master/framework/OutputProcessor.java && \
    grep -q 'Boolean.getBoolean("moves.keepDebugData")' gov/epa/otaq/moves/master/framework/OutputProcessor.java && \
    ant compileall && \
    ant go64 && \
    test -x calc/externalcalculatorgo64.exe && test -x generators/externalgenerator64.exe && \
    rm -rf /tmp/go /tmp/gocache /tmp/gopath /root/.config/go && hash -r && \
    ! command -v go

# rclone, for sync mode (MOVES_IO=sync: task_fetch_inputs.sh, task_push_outputs.sh). 3.1.0 installs the
# official rclone release, pinned by version and by the SHA-256 that rclone publishes (SHA256SUMS on
# github.com/rclone/rclone/releases and downloads.rclone.org), instead of Ubuntu's rclone 1.50.2.
# The build arguments do not start with RCLONE_: rclone reads RCLONE_<FLAG> variables as flags.
ARG PIN_RCLONE_VERSION=1.76.0
ARG PIN_RCLONE_SHA256=b00f00b3266c3764413afe599d3ec316f6f43b3e0ea8a0bc1d186d2133e46df7
RUN set -e && \
    curl -fsSL "https://github.com/rclone/rclone/releases/download/v${PIN_RCLONE_VERSION}/rclone-v${PIN_RCLONE_VERSION}-linux-amd64.zip" -o /tmp/rclone.zip && \
    echo "${PIN_RCLONE_SHA256}  /tmp/rclone.zip" | sha256sum -c - && \
    unzip -q -j /tmp/rclone.zip "rclone-v${PIN_RCLONE_VERSION}-linux-amd64/rclone" -d /usr/bin && \
    chmod 0755 /usr/bin/rclone && rm -f /tmp/rclone.zip && \
    test "$(rclone version | head -1)" = "rclone v${PIN_RCLONE_VERSION}"


# ESTABLISH WORKING DIRECTORY
WORKDIR /cat

# COPY IN MATERIALS
COPY scripts ./scripts

# Make scripts executable
RUN chmod +x /cat/scripts/*.sh


# gargle -> fs needs libuv headers (fs 1.6+ no longer bundles libuv); kept out of the big apt layer so the cache holds.
RUN apt-get update && apt-get install -y --no-install-recommends libuv1-dev && rm -rf /var/lib/apt/lists/*
# Google R packages: catr 0.2.0 imports them (catr/R/api_functions.R). Kept, pinned to v2 versions,
# until a catr release drops the imports (backlog; Tim 2026-11-02). They are R-only and small.
RUN R -e "remotes::install_version('gargle', version = '1.5.2', repos = 'http://cran.us.r-project.org'); library(gargle)"
RUN R -e "remotes::install_version('googleAuthR', version = '2.0.2', repos = 'http://cran.us.r-project.org'); library(googleAuthR)"
RUN R -e "remotes::install_version('googleCloudStorageR', version = '0.7.0', repos = 'http://cran.us.r-project.org'); library(googleCloudStorageR)"
# Fail loudly if the MariaDB client package did not install (the v3 build of 2026-11-02 failed on catr for this reason).
RUN R -e "library(RMariaDB); library(RMySQL); library(httr)"
RUN Rscript /cat/scripts/task_install_catr.R && Rscript -e "library(catr); cat('catr', as.character(packageVersion('catr')), '\n')"

# Label the image
# GIT_REVISION: the moves_anywhere commit the image is built from (--build-arg GIT_REVISION=<sha>).
ARG GIT_REVISION=unknown
LABEL title="moves-anywhere"
LABEL description="standalone docker-moves image for customized MOVES estimation on any OS. Cloud version."
LABEL version="3.1.0"
LABEL org.opencontainers.image.version="3.1.0"
LABEL org.opencontainers.image.description="moves-anywhere v3.1.0: EPA MOVES on any OS in one Docker container (ticket mode, run manifest, replication kit)."
LABEL org.opencontainers.image.source="https://github.com/timothyfraser/moves_anywhere"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.revision="${GIT_REVISION}"
LABEL maintainer="Tim Fraser"
LABEL org.opencontainers.image.authors="tmf77@cornell.edu"

# Specify volumes to be mounted
VOLUME /cat/inputs
VOLUME /cat/scripts
VOLUME /cat/secret

# Set entrypoint so it opens in bash on request
ENTRYPOINT ["/bin/bash"]

# Set the default command to be launch.sh
# ENTRYPOINT is bash, so CMD is the script path only (the old "bash -c" form made bash try to execute bash: exit 126).
CMD [ "/cat/scripts/launch.sh" ]
