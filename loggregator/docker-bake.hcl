variable "REGISTRY_PREFIX" {
  default = ""
}

variable "LOGGREGATOR_RELEASE_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/loggregator-release
  default = "107.0.30"
}

group "default" {
  targets = ["loggregator"]
}

target "loggregator" {
  dockerfile = "${component}.Dockerfile"
  tags = [ "${REGISTRY_PREFIX}${component}:latest", "${REGISTRY_PREFIX}${component}:${LOGGREGATOR_RELEASE_VERSION}"]
  name = component

  matrix = {
    "component" = [ "doppler", "reverse-log-proxy", "reverse-log-proxy-gateway", "traffic-controller" ]
  }

  contexts = {
    "src" = "https://github.com/cloudfoundry/loggregator-release.git#v${LOGGREGATOR_RELEASE_VERSION}:src"
  }
}
