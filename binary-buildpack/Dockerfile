FROM --platform=$BUILDPLATFORM golang:1.25 AS builder

ARG TARGETOS

COPY --from=src . /buildpack/src
WORKDIR /buildpack/src

COPY --from=libbuildpack . /buildpack-packager

RUN cd /buildpack-packager && GOOS=${TARGETOS} GOARCH=amd64 go build -o /usr/local/buildpack-packager packager/buildpack-packager/main.go

RUN GOARCH=amd64 /usr/local/buildpack-packager build -stack cflinuxfs4

FROM scratch

COPY --from=builder --chmod=0755 /buildpack/src/*.zip /binary-buildpack.zip
