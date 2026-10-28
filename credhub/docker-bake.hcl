variable "REGISTRY_PREFIX" {
  default = ""
}

variable "CREDHUB_RELEASE_VERSION" {
  # renovate: dataSource=github-releases depName=pivotal/credhub-release
  default = "2.15.28"
}

variable "IMAGE_VERSION" {
  # renovate: dataSource=github-releases depName=pivotal/credhub-release
  default = "2.15.28"
}

group "default" {
  targets = ["credhub"]
}

target "credhub" {
  dockerfile = "credhub.Dockerfile"
  tags = [ "${REGISTRY_PREFIX}credhub:latest", "${REGISTRY_PREFIX}credhub:${IMAGE_VERSION}" ]

  contexts = {
    "src" = "https://github.com/pivotal/credhub-release.git#${CREDHUB_RELEASE_VERSION}:src/credhub"
    "files" = "files"
  }
}
