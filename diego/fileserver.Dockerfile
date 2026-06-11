FROM --platform=$BUILDPLATFORM golang:1.26 AS builder

ARG TARGETARCH

COPY --from=src . /diego/src
COPY --from=config . /diego/config
WORKDIR /diego/src/code.cloudfoundry.org

RUN apt update && apt install -y xz-utils flex bison

SHELL ["/usr/bin/env", "bash", "-eux", "-o", "pipefail", "-c"]


RUN <<-EOF
    case ${TARGETARCH} in
      "amd64")  export ENVOY_ARCH=linux-x86_64  ;;
      "arm64")  export ENVOY_ARCH=linux-aarch_64 ;;
      *)        echo "unsupported architecture ${TARGETARCH}" ;;
    esac

    mkdir -p /tmp/final/cf-assets

    # sshd
    CGO_ENABLED=0 go build -o /tmp/final/diego-sshd -a -installsuffix static code.cloudfoundry.org/diego-ssh/cmd/sshd

    # healthcheck
    CGO_ENABLED=0 go build -o /tmp/final/healthcheck -a -installsuffix static code.cloudfoundry.org/healthcheck/cmd/healthcheck
    tar -czf /tmp/final/cf-assets/healthcheck.tgz -C /tmp/final healthcheck

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
    go build -ldflags '-linkmode external' -o /tmp/final/cf-pcap -a -installsuffix static code.cloudfoundry.org/cf-pcap
    
    # envoy proxy
    ENVOY_VERSION=$(sed -nE 's#^proxy/envoy-.*-([0-9]+\.[0-9]+\.[0-9]+)\.tgz:$#\1#p' /diego/config/blobs.yml)
    wget -O /tmp/envoy https://github.com/envoyproxy/envoy/releases/download/v${ENVOY_VERSION}/envoy-${ENVOY_VERSION}-${ENVOY_ARCH}
    tar -czf /tmp/final/cf-assets/proxy.tgz -C /tmp envoy

    # lifecycles
    ## cnbapplifecycle
    cd /diego/src/cnbapplifecycle
    CGO_ENABLED=0 go build -o /tmp/final/cnb_app_lifecycle/ -ldflags "-s -w" -a -installsuffix static code.cloudfoundry.org/cnbapplifecycle/cmd/builder code.cloudfoundry.org/cnbapplifecycle/cmd/launcher
    
    cp /tmp/final/healthcheck /tmp/final/cnb_app_lifecycle/healthcheck
    cp /tmp/final/diego-sshd /tmp/final/cnb_app_lifecycle/diego-sshd
    cp /tmp/final/cf-pcap /tmp/final/cnb_app_lifecycle/cf-pcap

    ## buildpack_app_lifecycle
    cd /diego/src/code.cloudfoundry.org
    CGO_ENABLED=0 go build -o /tmp/final/buildpack_app_lifecycle/builder -a -installsuffix static code.cloudfoundry.org/buildpackapplifecycle/builder
    CGO_ENABLED=0 go build -o /tmp/final/buildpack_app_lifecycle/launcher -a -installsuffix static code.cloudfoundry.org/buildpackapplifecycle/launcher
    CGO_ENABLED=0 go build -o /tmp/final/buildpack_app_lifecycle/shell -a -installsuffix static code.cloudfoundry.org/buildpackapplifecycle/shell/shell

    cp /tmp/final/healthcheck /tmp/final/buildpack_app_lifecycle/healthcheck
    cp /tmp/final/diego-sshd /tmp/final/buildpack_app_lifecycle/diego-sshd
    cp /tmp/final/cf-pcap /tmp/final/buildpack_app_lifecycle/cf-pcap

    ## docker_app_lifecycle
    CGO_ENABLED=0 go build -o /tmp/final/docker_app_lifecycle/builder  -a -installsuffix static code.cloudfoundry.org/dockerapplifecycle/builder
    CGO_ENABLED=0 go build -o /tmp/final/docker_app_lifecycle/launcher -a -installsuffix static code.cloudfoundry.org/dockerapplifecycle/launcher

    cp /tmp/final/healthcheck /tmp/final/docker_app_lifecycle/healthcheck
    cp /tmp/final/diego-sshd /tmp/final/docker_app_lifecycle/diego-sshd
    cp /tmp/final/cf-pcap /tmp/final/docker_app_lifecycle/cf-pcap
EOF


FROM nginx:latest

COPY --from=builder /tmp/final /fileserver
