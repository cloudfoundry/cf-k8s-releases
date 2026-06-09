variable "REGISTRY_PREFIX" {
  default = ""
}

variable "ROUTING_RELEASE_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/routing-release
  default = "0.384.0"
}

group "default" {
  targets = ["routing"]
}

target "routing" {
  dockerfile = "${component}.Dockerfile"
  tags = [ "${REGISTRY_PREFIX}${component}:latest", "${REGISTRY_PREFIX}${component}:${ROUTING_RELEASE_VERSION}"]
  name = component

  matrix = {
    "component" = [ "gorouter", "route-registrar", "cf-tcp-router", "routing-api" ]
  }

  contexts = {
    "src" = "https://github.com/cloudfoundry/routing-release.git#v${ROUTING_RELEASE_VERSION}:src"
    "files" = "files"
  }
}
