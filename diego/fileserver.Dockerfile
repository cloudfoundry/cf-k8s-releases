FROM --platform=$BUILDPLATFORM golang:1.27 AS builder

ARG TARGETOS
ARG TARGETARCH

COPY --from=src . /diego/src
COPY --from=config . /diego/config
WORKDIR /diego/src/code.cloudfoundry.org

RUN apt update && apt install -y xz-utils flex bison

SHELL ["/usr/bin/env", "bash", "-eux", "-o", "pipefail", "-c"]


RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /tmp/fileserver -ldflags "-w -s" code.cloudfoundry.org/fileserver/cmd/file-server

RUN <<-EOF
    mkdir -p /tmp/cnb_app_lifecycle
    mkdir -p /tmp/buildpack_app_lifecycle
    mkdir -p /tmp/docker_app_lifecycle
    mkdir -p /tmp/final/cnb_app_lifecycle
    mkdir -p /tmp/final/buildpack_app_lifecycle
    mkdir -p /tmp/final/docker_app_lifecycle

    # sshd
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /tmp/diego-sshd -ldflags "-w -s" code.cloudfoundry.org/diego-ssh/cmd/sshd

    cp /tmp/diego-sshd /tmp/cnb_app_lifecycle
    cp /tmp/diego-sshd /tmp/buildpack_app_lifecycle
    cp /tmp/diego-sshd /tmp/docker_app_lifecycle

    # healthcheck
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /tmp/healthcheck -ldflags "-w -s" code.cloudfoundry.org/healthcheck/cmd/healthcheck

    cp /tmp/healthcheck /tmp/cnb_app_lifecycle
    cp /tmp/healthcheck /tmp/buildpack_app_lifecycle
    cp /tmp/healthcheck /tmp/docker_app_lifecycle

    # cf-pcap
    LIBPCAP_VERSION=$(sed -nE 's#^libpcap/libpcap-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.xz:$#\1#p' /diego/config/blobs.yml)

    wget -O /tmp/libpcap.tar.xz https://www.tcpdump.org/release/libpcap-${LIBPCAP_VERSION}.tar.xz   
    tar -xf /tmp/libpcap.tar.xz -C /tmp
    LIBPCAP_DIR=$(ls -d /tmp/libpcap-*)

    pushd ${LIBPCAP_DIR}
      ./configure
      make
    popd

    export CGO_CFLAGS="-I$LIBPCAP_DIR"
    export CGO_LDFLAGS="-L$LIBPCAP_DIR -static"
    go build -ldflags '-linkmode external' -o /tmp/cf-pcap -ldflags "-w -s" code.cloudfoundry.org/cf-pcap

    cp /tmp/cf-pcap /tmp/cnb_app_lifecycle
    cp /tmp/cf-pcap /tmp/buildpack_app_lifecycle
    cp /tmp/cf-pcap /tmp/docker_app_lifecycle

    # lifecycles
    ## cnbapplifecycle
    cd /diego/src/code.cloudfoundry.org/vendor/code.cloudfoundry.org/cnbapplifecycle
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /tmp/cnb_app_lifecycle/ -ldflags "-s -w" -ldflags "-w -s" code.cloudfoundry.org/cnbapplifecycle/cmd/builder code.cloudfoundry.org/cnbapplifecycle/cmd/launcher

    tar -czf /tmp/final/cnb_app_lifecycle/cnb_app_lifecycle.tgz -C /tmp/cnb_app_lifecycle builder launcher healthcheck diego-sshd cf-pcap

    ## buildpack_app_lifecycle
    cd /diego/src/code.cloudfoundry.org
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /tmp/buildpack_app_lifecycle/builder -ldflags "-w -s" code.cloudfoundry.org/buildpackapplifecycle/builder
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /tmp/buildpack_app_lifecycle/launcher -ldflags "-w -s" code.cloudfoundry.org/buildpackapplifecycle/launcher
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /tmp/buildpack_app_lifecycle/shell -ldflags "-w -s" code.cloudfoundry.org/buildpackapplifecycle/shell/shell

    tar -czf /tmp/final/buildpack_app_lifecycle/buildpack_app_lifecycle.tgz -C /tmp/buildpack_app_lifecycle builder launcher shell healthcheck diego-sshd cf-pcap

    ## docker_app_lifecycle
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /tmp/docker_app_lifecycle/builder  -ldflags "-w -s" code.cloudfoundry.org/dockerapplifecycle/builder
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /tmp/docker_app_lifecycle/launcher -ldflags "-w -s" code.cloudfoundry.org/dockerapplifecycle/launcher

    tar -czf /tmp/final/docker_app_lifecycle/docker_app_lifecycle.tgz -C /tmp/docker_app_lifecycle builder launcher healthcheck diego-sshd cf-pcap
EOF


FROM gcr.io/distroless/static:latest

COPY --from=builder /tmp/final /static
COPY --from=builder /tmp/fileserver /fileserver

ENTRYPOINT ["/fileserver"]
