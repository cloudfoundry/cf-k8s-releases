FROM --platform=$BUILDPLATFORM golang:alpine AS builder

ARG TARGETOS TARGETARCH

COPY --from=src . /loggregator-agent-release/src
WORKDIR /loggregator-agent-release/src

RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /usr/local/bin/forwarder-agent ./cmd/forwarder-agent

FROM ubuntu:latest

COPY --from=builder /usr/local/bin/forwarder-agent /usr/local/bin/forwarder-agent

ENTRYPOINT [ "/usr/local/bin/forwarder-agent" ]
