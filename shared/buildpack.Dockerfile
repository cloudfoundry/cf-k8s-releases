FROM ubuntu:latest AS builder

ARG VERSION
ARG NAME
SHELL ["/usr/bin/env", "bash", "-eux", "-o", "pipefail", "-c"]

RUN <<-EOF
    apt update && apt install -y curl jq tar yq
    export PACKAGE_NAME=$(curl -s "https://storage.googleapis.com/storage/v1/b/cf-deployment-compiled-releases/o?matchGlob=${NAME}-${VERSION}%2A" | jq -r '.items[0].name')
    curl -o /${NAME}.tar.gz -L "https://storage.googleapis.com/cf-deployment-compiled-releases/$PACKAGE_NAME"
    tar -xzf /${NAME}.tar.gz -C /tmp && rm /${NAME}.tar.gz

    mkdir /final
    for package in $(yq -r '.compiled_packages[].name' /tmp/release.MF); do
        mkdir /$package && tar -xzf /tmp/compiled_packages/$package.tgz -C /$package
        mv /$package/*.zip /final/$package.zip
    done

EOF

FROM scratch

COPY --from=builder --chmod=0755 /final /
