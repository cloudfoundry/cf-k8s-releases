FROM --platform=$BUILDPLATFORM golang:alpine AS builder

ARG TARGETOS TARGETARCH

COPY --from=src . /networking-release/src
WORKDIR /networking-release/src/code.cloudfoundry.org

RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /usr/local/bin/bosh-dns-adapter code.cloudfoundry.org/bosh-dns-adapter

FROM busybox:1.37.0-musl@sha256:5cec3fc171c87218698e85a52af7087de727372aae264a787b8112901a5b0092 AS healthcheck

FROM gcr.io/distroless/static:latest

COPY --from=builder /usr/local/bin/bosh-dns-adapter /usr/local/bin/bosh-dns-adapter
COPY --from=healthcheck /bin/busybox /usr/local/bin/busybox

ENTRYPOINT [ "/usr/local/bin/bosh-dns-adapter" ]
CMD [ "-c", "/bosh-dns-adapter/bosh-dns-adapter.json" ]
