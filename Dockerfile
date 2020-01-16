####################
## STEP 1: Build  ##
####################
# Image Base
FROM centos:7 AS builder

# Git install
RUN yum install -y git \
    # Python 3.6 repository and packages
    && yum install -y yum-utils https://centos7.iuscommunity.org/ius-release.rpm \
    && yum makecache \
    && yum install -y python36u openssl \
    && yum clean all \
    && rm -rf /var/cache/yum \
    # JDK and JVM install
    && curl --retry 8 -o /openjdk.tar.gz https://download.java.net/java/GA/jdk12.0.1/69cfe15208a647278a19ef0990eea691/12/GPL/openjdk-12.0.1_linux-x64_bin.tar.gz \
    && echo "151eb4ec00f82e5e951126f572dc9116104c884d97f91be14ec11e85fc2dd626 */openjdk.tar.gz" | sha256sum -c - \
    && tar -C /opt -zxf /openjdk.tar.gz \
    && rm /openjdk.tar.gz \
    # REF: https://github.com/elastic/elasticsearch-docker/issues/171
    && ln -sf /etc/pki/ca-trust/extracted/java/cacerts /opt/jdk-12.0.1/lib/security/cacerts

ENV JAVA_HOME /opt/jdk-12.0.1
ENV PATH=$PATH:\$JAVA_HOME/bin


# CrateDB-CE Compilation
WORKDIR /tmp
RUN git clone https://github.com/crate/crate.git
WORKDIR /tmp/crate
RUN git submodule update --init \
    #### checkout version
    && git checkout 4.0.10 \
    && ./gradlew clean communityEditionDistTar \
    # Copy Tar distribution file
    && cp /tmp/crate/app/build/distributions/crate-ce-*.tar.gz /tmp/crate-ce.tar.gz

WORKDIR /tmp
RUN tar xzf crate-ce.tar.gz


####################
## STEP 2: Run    ##
####################
FROM centos:7

RUN groupadd crate && useradd -u 1000 -g crate -d /crate crate

# install crash
RUN curl -fSL -O https://cdn.crate.io/downloads/releases/crash_standalone_0.24.2 \
    && curl -fSL -O https://cdn.crate.io/downloads/releases/crash_standalone_0.24.2.asc \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 90C23FC6585BC0717F8FBFC37FAAE51A06F6EAEB \
    && gpg --batch --verify crash_standalone_0.24.2.asc crash_standalone_0.24.2 \
    && rm -rf "$GNUPGHOME" crash_standalone_0.24.2.asc \
    && mv crash_standalone_0.24.2 /usr/local/bin/crash \
    && chmod +x /usr/local/bin/crash \
    # Python3 Env
    && yum install -y python36u openssl \
    && yum clean all \
    && rm -rf /var/cache/yum \
    && ln -sf /usr/bin/python3.6 /usr/bin/python3 \
    && ln -sf /usr/bin/python3.6 /usr/bin/python \
    # JVM Install
    && curl --retry 8 -o /openjdk.tar.gz https://download.java.net/java/GA/jdk12.0.1/69cfe15208a647278a19ef0990eea691/12/GPL/openjdk-12.0.1_linux-x64_bin.tar.gz \
    && echo "151eb4ec00f82e5e951126f572dc9116104c884d97f91be14ec11e85fc2dd626 */openjdk.tar.gz" | sha256sum -c - \
    && tar -C /opt -zxf /openjdk.tar.gz \
    && rm /openjdk.tar.gz \
    # REF: https://github.com/elastic/elasticsearch-docker/issues/171
    && ln -sf /etc/pki/ca-trust/extracted/java/cacerts /opt/jdk-12.0.1/lib/security/cacerts \
    && mkdir -p /data/data /data/log \
    && chown -R crate:crate /data

ENV JAVA_HOME /opt/jdk-12.0.1
ENV PATH=$PATH:\$JAVA_HOME/bin

VOLUME /data

WORKDIR /data

# Run CrateDB-CE
USER crate
COPY --from=builder --chown=crate:crate /tmp/crate-ce* /crate/
ENV PATH=$PATH:/crate/bin

# Default heap size for Docker, can be overwritten by args
ENV CRATE_HEAP_SIZE 512M

# http: 4200 tcp
# transport: 4300 tcp
# postgres protocol ports: 5432 tcp
EXPOSE 4200 4300 5432

LABEL maintainer="implus.co <technology@implustech.com>" \
    org.label-schema.schema-version="1.0" \
    org.label-schema.build-date="2020-01-16T13:56:43.986536" \
    org.label-schema.name="crate" \
    org.label-schema.description="CrateDB is a distributed SQL database handles massive amounts of machine data in real-time." \
    org.label-schema.url="https://crate.io/products/cratedb/" \
    org.label-schema.vcs-url="https://github.com/implustech/crate-ce" \
    org.label-schema.vendor="Crate.io" \
    org.label-schema.version="4.0.10"

COPY docker-entrypoint.sh /

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["crate"]
