FROM gcc:15 AS gccbuild

ARG TAR_VERSION=1.35

COPY --from=tar . /src
WORKDIR /src

ENV LDFLAGS=-static
ENV FORCE_UNSAFE_CONFIGURE=1
ENV CC="musl-gcc -static"

RUN apt update && apt install musl musl-dev musl-tools -y && tar -xJf context && \
    cd ./tar-${TAR_VERSION} && ./configure && make && mv src/tar /src/tar

FROM --platform=$BUILDPLATFORM golang:1 AS builder

ARG TARGETOS TARGETARCH

COPY --from=src ./code.cloudfoundry.org /src
WORKDIR /src

RUN go mod vendor && go mod download

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags "-w -s" -o bin/rep code.cloudfoundry.org/rep/cmd/rep
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags "-w -s" -o bin/watcher code.cloudfoundry.org/rep/cmd/watch
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -ldflags "-w -s" -o bin/untar code.cloudfoundry.org/rep/cmd/untar

FROM ubuntu:26.04
ARG TARGETARCH
RUN apt-get update && apt-get install -y \
    ca-certificates \
    tzdata \
    && \
    update-ca-certificates

COPY --from=builder /src/bin/rep /bin/rep
COPY --from=builder /src/bin/watcher /bin/watcher
COPY --from=builder /src/bin/untar /bin/untar
COPY --from=gccbuild /src/tar /bin/tar

EXPOSE 8080 443

ENTRYPOINT [ "/bin/rep" ]