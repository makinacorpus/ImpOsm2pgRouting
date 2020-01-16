FROM debian:buster-slim

RUN apt-get update && \
    apt-get install -y \
        libleveldb-dev \
        libgeos-dev \
        libprotobuf-dev \
        postgresql \
        postgresql-client \
        wget && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/imposm
RUN wget https://github.com/omniscale/imposm3/releases/download/v0.10.0/imposm-0.10.0-linux-x86-64.tar.gz && \
    tar --strip 1 -xvzf imposm-0.10.0-linux-x86-64.tar.gz && \
    rm imposm-0.10.0-linux-x86-64.tar.gz

ENV IMPORT_DIR=/import \
    IMPOSM_CACHE_DIR=/cache \
    MAPPING_YAML=/mapping/mapping.yaml \
    DIFF_DIR=/import

ADD imposm .

WORKDIR /opt/imposm2pgrouting
ADD pgRouting .

WORKDIR /opt/docker
ADD docker .

VOLUME [/tmp/imposm]

ENV PATH=".;${PATH}"
CMD ["bash"]
