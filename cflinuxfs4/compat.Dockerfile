ARG STACK_VERSION
ARG STACK_NAME
ARG package_args='--allow-downgrades --allow-remove-essential --allow-change-held-packages --no-install-recommends'

FROM --platform=amd64 cloudfoundry/${STACK_NAME}:${STACK_VERSION}

COPY --from=src . /tmp/packages

RUN apt-get -y $package_args update && \
  apt-get -y $package_args install $(cat /tmp/packages/cflinuxfs4-compat) && \
  apt-get clean && \
  find /usr/share/doc/*/* ! -name copyright | xargs rm -rf && \
  rm -rf /tmp/packages
