FROM ubuntu:20.04

# Build arguments
# MOVES_COMMIT: the exact USEPA/EPA_MOVES_Model commit baked into the image (the one v2 shipped).
# Debug data (MOVES keepDebugData) is a RUNTIME switch (parameters.json "debug": true); see task_launch_moves.sh.
ARG MOVES_COMMIT=2c4cd1ab31b53bc9731492544fcbd0a6e47b970a

# Create directory
RUN mkdir cat

# Create and change to this directory
WORKDIR cat

# Set environment variable so apt-get runs without interactive dialogue
ARG DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    mariadb-server \
    openjdk-11-jdk \
    golang-go \
    git \
    ant \
    unzip \
    sudo \
    libmariadb-dev \
    libxml2-dev \
    rclone \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Upgrade R
# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
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


# Clone the EPA MOVES Model repository and pin it to MOVES_COMMIT
RUN git clone https://github.com/USEPA/EPA_MOVES_Model.git && \
    git -C EPA_MOVES_Model checkout "$MOVES_COMMIT" && \
    git -C EPA_MOVES_Model rev-parse HEAD

# Unzip database dumpfile
RUN unzip EPA_MOVES_Model/database/Setup/movesdb20241112.zip -d EPA_MOVES_Model/database/Setup

# Copy your files to the container
COPY setenv.sh /cat/EPA_MOVES_Model
# Setting mysql/mariadb configurations based on MOVES repository README
COPY my.cnf /etc/my.cnf

# Giving group permissions recursively to /cat and giving mysql ownership recursively
RUN chown -R mysql:mysql /cat
RUN chmod -R 6777 /cat

# Setup Databases
COPY setupdb.sh /cat/setupdb.sh
# Make setupdb.sh executable
RUN chmod +x /cat/setupdb.sh
SHELL ["/bin/bash", "-c"]
RUN /cat/setupdb.sh

# Compile MOVES (Java and Go) at build time, so no run compiles anything.
# D29: keepDebugData becomes a JVM property, default false, so a RUN can opt in with
# JAVA_TOOL_OPTIONS=-Dmoves.keepDebugData=true (task_launch_moves.sh sets it when parameters.json has "debug": true).
RUN cd /cat/EPA_MOVES_Model && \
    sed -i 's/static final boolean keepDebugData = false;/static final boolean keepDebugData = Boolean.getBoolean("moves.keepDebugData");/' gov/epa/otaq/moves/master/framework/OutputProcessor.java && \
    grep -q 'Boolean.getBoolean("moves.keepDebugData")' gov/epa/otaq/moves/master/framework/OutputProcessor.java && \
    ant compileall && \
    ant go64


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
LABEL title="moves-anywhere"
LABEL description="standalone docker-moves image for customized MOVES estimation on any OS. Cloud version."
LABEL version="3.0-dev"
LABEL status="development"
LABEL org.opencontainers.image.description="moves-anywhere v3 is UNDER DEVELOPMENT and not yet released for public use; v2 is the supported image."
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
