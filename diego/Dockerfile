FROM --platform=$BUILDPLATFORM golang:alpine AS builder

ARG TARGETOS TARGETARCH COMPONENT CMD_PKG

COPY --from=src . /diego-release/src
WORKDIR /diego-release/src/code.cloudfoundry.org

RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /usr/local/bin/$CMD_PKG code.cloudfoundry.org/$COMPONENT/cmd/$CMD_PKG
RUN ln -s /usr/local/bin/$CMD_PKG /entrypoint

FROM gcr.io/distroless/static:latest

ARG CMD_PKG

COPY --from=builder /usr/local/bin/$CMD_PKG /usr/local/bin/$CMD_PKG
COPY --from=builder /entrypoint /entrypoint

ENTRYPOINT [ "/entrypoint" ]
