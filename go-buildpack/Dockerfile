FROM --platform=$BUILDPLATFORM golang:1.25 AS builder

ARG TARGETOS TARGETARCH

COPY --from=src . /buildpack/src
WORKDIR /buildpack/src

COPY --from=libbuildpack . /buildpack-packager

RUN cd /buildpack-packager && go build -o /usr/local/buildpack-packager packager/buildpack-packager/main.go

RUN /usr/local/buildpack-packager build -any-stack
RUN  mv *.zip go-buildpack.zip

FROM scratch

COPY --from=builder --chmod=0755 /buildpack/src/*.zip /
