variable "REGISTRY_PREFIX" {
  default = ""
}

variable "OTEL_COLLECTOR_RELEASE_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/otel-collector-release
  default = "0.11.10"
}

group "default" {
  targets = ["otel-collector"]
}

target "otel-collector" {
  dockerfile = "${component}.Dockerfile"
  tags = [ "${REGISTRY_PREFIX}${component}:latest", "${REGISTRY_PREFIX}${component}:${OTEL_COLLECTOR_RELEASE_VERSION}"]
  name = component

  matrix = {
    "component" = [ "otel-collector" ]
  }

  contexts = {
    "src" = "https://github.com/cloudfoundry/otel-collector-release.git#v${OTEL_COLLECTOR_RELEASE_VERSION}:src"
  }
}
