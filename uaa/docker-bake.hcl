variable "REGISTRY_PREFIX" {
  default = ""
}

variable "UAA_RELEASE_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/uaa-release
  default = "79.3.0"
}

group "default" {
  targets = ["uaa"]
}

target "uaa" {
  dockerfile = "uaa.Dockerfile"
  tags = [ "${REGISTRY_PREFIX}uaa:latest", "${REGISTRY_PREFIX}uaa:${UAA_RELEASE_VERSION}" ]
  args = {
    "UAA_RELEASE_VERSION" = UAA_RELEASE_VERSION
  }

  contexts = {
    "src" = "https://github.com/cloudfoundry/uaa-release.git#v${UAA_RELEASE_VERSION}:src/uaa"
    "files" = "files"
  }
}
