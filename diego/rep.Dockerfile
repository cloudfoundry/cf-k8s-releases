FROM gcc:15 AS gccbuild

ARG TAR_VERSION=1.35

WORKDIR /src

ADD https://github.com/cloudfoundry/guardian.git#main:rundmc/nstar ./nstar
RUN mkdir -p ./tar && curl -L http://ftp.gnu.org/gnu/tar/tar-${TAR_VERSION}.tar.xz | tar -xJ -C ./tar

ENV LDFLAGS=-static
ENV FORCE_UNSAFE_CONFIGURE=1

RUN apt update && apt install musl musl-dev musl-tools -y && \
    sed -i '/#include <unistd.h>/a #include <fcntl.h>' nstar/nstar.c && \
    make -C ./nstar nstar && \
    cd ./tar/tar-${TAR_VERSION} && CC="musl-gcc -static" ./configure && CC="musl-gcc -static" make && mv src/tar /src/tar/tar

FROM --platform=$BUILDPLATFORM golang:alpine AS repbuild

ARG TARGETOS TARGETARCH

COPY --from=src . /diego-release/src
WORKDIR /diego-release/src/code.cloudfoundry.org

RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /usr/local/bin/rep code.cloudfoundry.org/rep/cmd/rep

FROM --platform=$BUILDPLATFORM golang:alpine AS watcherbuild

ARG TARGETOS TARGETARCH

COPY --from=watcher . /k8s-garden-client
WORKDIR /k8s-garden-client

RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /usr/local/bin/watcher ./cmd/watch

FROM ubuntu:26.04

ARG TARGETARCH

RUN apt-get update && apt-get install -y \
    ca-certificates \
    tzdata \
    && \
    update-ca-certificates

COPY --from=repbuild /usr/local/bin/rep /bin/rep
COPY --from=watcherbuild /usr/local/bin/watcher /bin/watcher
COPY --from=gccbuild /src/nstar/nstar /bin/
COPY --from=gccbuild /src/tar/tar /bin/

EXPOSE 8080 443

ENTRYPOINT [ "/bin/rep" ]
