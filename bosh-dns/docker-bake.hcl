variable "REGISTRY_PREFIX" {
    default = ""
}

group "default" {
    targets = [ "bosh-dns" ]
}

variable "BOSH_DNS_RELEASE_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/bosh-dns-release
  default = "1.39.25"
}

target "bosh-dns" {
  dockerfile = "${component}.Dockerfile"
  tags = [ "${REGISTRY_PREFIX}${component}:latest", "${REGISTRY_PREFIX}${component}:${BOSH_DNS_RELEASE_VERSION}"]
  name = component

  matrix = {
    "component" = [ "bosh-dns" ]
  }

  contexts = {
    "src" = "https://github.com/cloudfoundry/bosh-dns-release.git#v${BOSH_DNS_RELEASE_VERSION}:src"
  }
}
