# syntax=docker/dockerfile:1
# This dockerfile builds a 'live' zap docker image using the latest files in the repos
FROM --platform=linux/amd64 debian:bullseye-slim AS builder
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -q -y --fix-missing \
    openjdk-17-jdk wget curl unzip git && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir /zap-src

WORKDIR /zap-src
# Pull the ZAP repo and build ZAP with weekly add-ons
RUN git clone --depth 1 https://github.com/zaproxy/zaproxy.git && \
    cd zaproxy && \
    ZAP_WEEKLY_ADDONS_NO_TEST=true ./gradlew :zap:prepareDistWeekly

WORKDIR /zap
#ENV WEBSWING_VERSION 22.2.4
ENV WEBSWING_VERSION 23.1.1
ARG WEBSWING_URL=""
RUN if [ -z "$WEBSWING_URL" ] ; \
    then curl -s -L  "https://dev.webswing.org/files/public/webswing-examples-eval-${WEBSWING_VERSION}-distribution.zip" > webswing.zip; \
    else curl -s -L  "$WEBSWING_URL-${WEBSWING_VERSION}-distribution.zip" > webswing.zip; fi && \
    unzip webswing.zip && \
    rm webswing.zip && \
    mv webswing-* webswing && \
    # Remove Webswing bundled examples
    rm -Rf webswing/apps/

FROM debian:bullseye-slim AS final

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -q -y --fix-missing \
    make ant automake autoconf gcc g++ openjdk-17-jdk wget curl xmlstarlet unzip git openbox xterm net-tools \
    python3-pip python-is-python3 firefox-esr vim xvfb x11vnc sudo && \
    rm -rf /var/lib/apt/lists/*  && \
    useradd -u 1000 -d /home/zap -m -s /bin/bash zap && \
    echo zap:zap | chpasswd && \
    mkdir /zap  && \
    chown zap:zap /zap

RUN pip3 install --no-cache-dir --upgrade awscli pip python-owasp-zap-v2.4 pyyaml requests urllib3
#Change to the zap user so things get done as the right person (apart from copy)
USER zap
RUN mkdir /home/zap/.vnc
ARG TARGETARCH
ENV JAVA_HOME /usr/lib/jvm/java-11-openjdk-$TARGETARCH
ENV PATH $JAVA_HOME/bin:/zap/:$PATH
ENV ZAP_PATH /zap/zap.sh
# Default port for use with health check
ENV ZAP_PORT 8080
ENV IS_CONTAINERIZED true
ENV HOME /home/zap/
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

COPY --link --from=builder --chown=1000:1000 /zap-src/zaproxy/zap/build/distFilesWeekly/ /zap/
COPY --link --chown=1000:1000 zap* docker/CHANGELOG.md /zap/
COPY --link --from=builder --chown=1000:1000 /zap/webswing /zap/webswing
COPY --link --chown=1000:1000 docker/webswing.config /zap/webswing/
COPY --link --chown=1000:1000 docker/webswing.properties /zap/webswing/
COPY --link --chown=1000:1000 docker/policies /home/zap/.ZAP_D/policies/
COPY --link --chown=1000:1000 docker/policies /root/.ZAP_D/policies/
COPY --link --chown=1000:1000 docker/scripts /home/zap/.ZAP_D/scripts/
COPY --link --chown=1000:1000 docker/.xinitrc /home/zap/
COPY --link --chown=1000:1000 docker/zap* /zap/

RUN echo "zap2docker-live" > /zap/container && \
    chmod a+x /home/zap/.xinitrc && chmod +x /zap/zap.sh

WORKDIR /zap
HEALTHCHECK CMD curl --silent --output /dev/null --fail http://localhost:$ZAP_PORT/ || exit 1
