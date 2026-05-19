FROM ubuntu:latest AS builder

ARG DIEGO_RELEASE_VERSION
SHELL ["/usr/bin/env", "bash", "-eux", "-o", "pipefail", "-c"]

RUN <<-EOF
    apt update && apt install -y curl jq tar yq
    export PACKAGE_NAME=$(curl -s "https://storage.googleapis.com/storage/v1/b/cf-deployment-compiled-releases/o?matchGlob=diego-${DIEGO_RELEASE_VERSION}%2A" | jq -r '.items[0].name')
    curl -o /diego.tar.gz -L "https://storage.googleapis.com/cf-deployment-compiled-releases/$PACKAGE_NAME"
    mkdir /tmp/diego
    tar -xzf /diego.tar.gz -C /tmp/diego

    for pkg in buildpack_app_lifecycle cnb_app_lifecycle docker_app_lifecycle; do
        mkdir -p /tmp/final/$pkg
        tar -xzf /tmp/diego/compiled_packages/$pkg.tgz -C /tmp/final/$pkg
    done

    mkdir -p /tmp/final/cf-assets
    mv /tmp/diego/compiled_packages/healthcheck.tgz /tmp/final/cf-assets/healthcheck.tgz
    mv /tmp/diego/compiled_packages/proxy.tgz /tmp/final/cf-assets/proxy.tgz
EOF

FROM nginx:latest

COPY --from=builder /tmp/final /fileserver
