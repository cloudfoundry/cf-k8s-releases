FROM --platform=$BUILDPLATFORM ruby:3.3 AS builder

ARG TARGETOS

COPY --from=src . /buildpack/src
WORKDIR /buildpack/src

RUN bundle install
RUN bundle exec rake clean package

FROM scratch

ARG BUILDPACK_VERSION

COPY --from=builder --chmod=0755 /buildpack/src/build/*.zip /
