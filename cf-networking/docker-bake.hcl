variable "REGISTRY_PREFIX" {
    default = ""
}

group "default" {
    targets = [ "cf-networking" ]
}

variable "CF_NETWORKING_RELEASE_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/cf-networking-release
  default = "3.115.0"
}

target "cf-networking" {
  dockerfile = "${component}.Dockerfile"
  tags = [ "${REGISTRY_PREFIX}${component}:latest", "${REGISTRY_PREFIX}${component}:${CF_NETWORKING_RELEASE_VERSION}"]
  name = component

  matrix = {
    "component" = [ "policy-server", "bosh-dns-adapter", "service-discovery-controller" ]
  }

  contexts = {
    "src" = "https://github.com/cloudfoundry/cf-networking-release.git#v${CF_NETWORKING_RELEASE_VERSION}:src"
  }
}
