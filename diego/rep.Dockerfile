FROM gcc:15 AS gccbuild

ARG TAR_VERSION=1.35

COPY --from=tar . /src
WORKDIR /src

ENV LDFLAGS=-static
ENV FORCE_UNSAFE_CONFIGURE=1
ENV CC="musl-gcc -static"

RUN apt update && apt install musl musl-dev musl-tools -y && tar -xJf context && \
    cd ./tar-${TAR_VERSION} && ./configure && make && mv src/tar /src/tar

FROM --platform=$BUILDPLATFORM golang:1 AS builder

ARG TARGETOS TARGETARCH

COPY --from=src ./code.cloudfoundry.org /src
WORKDIR /src

RUN go mod vendor && go mod download

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags "-w -s" -o bin/rep code.cloudfoundry.org/rep/cmd/rep
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags "-w -s" -o bin/watcher code.cloudfoundry.org/rep/cmd/watch
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -ldflags "-w -s" -o bin/untar code.cloudfoundry.org/rep/cmd/untar
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags "-w -s" -o bin/healthcheck code.cloudfoundry.org/healthcheck/cmd/healthcheck

FROM alpine AS envoy
COPY --from=config . /config
RUN apk add --no-cache wget && \
    ENVOY_VERSION=$(sed -nE 's#^proxy/envoy-.*-([0-9]+\.[0-9]+\.[0-9]+)\.tgz:$#\1#p' /config/blobs.yml) && \
    wget -O /envoy https://github.com/envoyproxy/envoy/releases/download/v${ENVOY_VERSION}/envoy-${ENVOY_VERSION}-linux-x86_64 && \
    chmod +x /envoy

FROM registry.k8s.io/pause:3.10.2 AS pause

FROM ubuntu:26.04
ARG TARGETARCH
RUN apt-get update && apt-get install -y \
    ca-certificates \
    tzdata \
    && \
    update-ca-certificates

COPY --from=builder /src/bin/rep /bin/rep
COPY --from=builder /src/bin/watcher /bin/watcher
COPY --from=builder /src/bin/untar /bin/untar
COPY --from=builder /src/bin/healthcheck /bin/healthcheck
COPY --from=gccbuild /src/tar /bin/tar
COPY --from=envoy /envoy /bin/envoy
COPY --from=pause /pause /bin/init

EXPOSE 8080 443

ENTRYPOINT [ "/bin/rep" ]