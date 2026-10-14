FROM --platform=$BUILDPLATFORM golang:alpine AS builder

ARG TARGETOS TARGETARCH

COPY --from=src . /networking-release/src
WORKDIR /networking-release/src/code.cloudfoundry.org

RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /usr/local/bin/bosh-dns-adapter code.cloudfoundry.org/bosh-dns-adapter

FROM busybox:1.38.0-musl@sha256:ea2b9914a16a4ac1981994af97b318f7c7d4db76b580c56177f08bf76f4a0be8 AS healthcheck

FROM gcr.io/distroless/static:latest

COPY --from=builder /usr/local/bin/bosh-dns-adapter /usr/local/bin/bosh-dns-adapter
COPY --from=healthcheck /bin/busybox /usr/local/bin/busybox

ENTRYPOINT [ "/usr/local/bin/bosh-dns-adapter" ]
CMD [ "-c", "/bosh-dns-adapter/bosh-dns-adapter.json" ]
