FROM --platform=$BUILDPLATFORM golang:1.25 AS builder

ARG TARGETOS TARGETARCH

COPY --from=src . /otel-collector-release/src

WORKDIR /otel-collector-release/src/otel-collector

RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -mod=vendor -o /usr/local/bin/otel-collector .

FROM gcr.io/distroless/static:latest

COPY --from=builder /usr/local/bin/otel-collector /usr/local/bin/otel-collector

ENTRYPOINT [ "/usr/local/bin/otel-collector" ]
