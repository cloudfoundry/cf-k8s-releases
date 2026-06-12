FROM --platform=$BUILDPLATFORM golang:1.26 AS builder

ARG TARGETOS

COPY --from=src . /diego/src
COPY --from=config . /diego/config
WORKDIR /diego/src/code.cloudfoundry.org

RUN apt update && apt install -y xz-utils flex bison

SHELL ["/usr/bin/env", "bash", "-eux", "-o", "pipefail", "-c"]


RUN <<-EOF
    mkdir -p /tmp/cnb_app_lifecycle
    mkdir -p /tmp/buildpack_app_lifecycle
    mkdir -p /tmp/docker_app_lifecycle
    mkdir -p /tmp/final/cf-assets
    mkdir -p /tmp/final/v1/static/cnb_app_lifecycle
    mkdir -p /tmp/final/v1/static/buildpack_app_lifecycle
    mkdir -p /tmp/final/v1/static/docker_app_lifecycle

    # sshd
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=amd64 go build -o /tmp/diego-sshd -a -installsuffix static code.cloudfoundry.org/diego-ssh/cmd/sshd

    cp /tmp/diego-sshd /tmp/cnb_app_lifecycle
    cp /tmp/diego-sshd /tmp/buildpack_app_lifecycle
    cp /tmp/diego-sshd /tmp/docker_app_lifecycle

    # healthcheck
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=amd64 go build -o /tmp/healthcheck -a -installsuffix static code.cloudfoundry.org/healthcheck/cmd/healthcheck
    tar -czf /tmp/final/cf-assets/healthcheck.tgz -C /tmp healthcheck

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
    go build -ldflags '-linkmode external' -o /tmp/cf-pcap -a -installsuffix static code.cloudfoundry.org/cf-pcap

    cp /tmp/cf-pcap /tmp/cnb_app_lifecycle
    cp /tmp/cf-pcap /tmp/buildpack_app_lifecycle
    cp /tmp/cf-pcap /tmp/docker_app_lifecycle
    
    # envoy proxy
    ENVOY_VERSION=$(sed -nE 's#^proxy/envoy-.*-([0-9]+\.[0-9]+\.[0-9]+)\.tgz:$#\1#p' /diego/config/blobs.yml)
    wget -O /tmp/envoy https://github.com/envoyproxy/envoy/releases/download/v${ENVOY_VERSION}/envoy-${ENVOY_VERSION}-linux-x86_64
    chmod +x /tmp/envoy
    tar -czf /tmp/final/cf-assets/proxy.tgz -C /tmp envoy

    # lifecycles
    ## cnbapplifecycle
    cd /diego/src/cnbapplifecycle
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=amd64 go build -o /tmp/cnb_app_lifecycle/ -ldflags "-s -w" -a -installsuffix static code.cloudfoundry.org/cnbapplifecycle/cmd/builder code.cloudfoundry.org/cnbapplifecycle/cmd/launcher
    
    tar -czf /tmp/final/v1/static/cnb_app_lifecycle/cnb_app_lifecycle.tgz -C /tmp/cnb_app_lifecycle builder launcher healthcheck diego-sshd cf-pcap

    ## buildpack_app_lifecycle
    cd /diego/src/code.cloudfoundry.org
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=amd64 go build -o /tmp/buildpack_app_lifecycle/builder -a -installsuffix static code.cloudfoundry.org/buildpackapplifecycle/builder
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=amd64 go build -o /tmp/buildpack_app_lifecycle/launcher -a -installsuffix static code.cloudfoundry.org/buildpackapplifecycle/launcher
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=amd64 go build -o /tmp/buildpack_app_lifecycle/shell -a -installsuffix static code.cloudfoundry.org/buildpackapplifecycle/shell/shell

    tar -czf /tmp/final/v1/static/buildpack_app_lifecycle/buildpack_app_lifecycle.tgz -C /tmp/buildpack_app_lifecycle builder launcher shell healthcheck diego-sshd cf-pcap

    ## docker_app_lifecycle
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=amd64 go build -o /tmp/docker_app_lifecycle/builder  -a -installsuffix static code.cloudfoundry.org/dockerapplifecycle/builder
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=amd64 go build -o /tmp/docker_app_lifecycle/launcher -a -installsuffix static code.cloudfoundry.org/dockerapplifecycle/launcher

    tar -czf /tmp/final/v1/static/docker_app_lifecycle/docker_app_lifecycle.tgz -C /tmp/docker_app_lifecycle builder launcher healthcheck diego-sshd cf-pcap
EOF


FROM nginx:latest

COPY --from=builder /tmp/final /fileserver
