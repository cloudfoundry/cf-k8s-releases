variable "REGISTRY_PREFIX" {
  default = ""
}

variable "CREDHUB_RELEASE_VERSION" {
  # renovate: dataSource=github-releases depName=pivotal/credhub-release
  default = "2.15.8"
}

group "default" {
  targets = ["credhub"]
}

target "credhub" {
  dockerfile = "credhub.Dockerfile"
  tags = [ "${REGISTRY_PREFIX}credhub:latest", "${REGISTRY_PREFIX}credhub:${CREDHUB_RELEASE_VERSION}" ]

  contexts = {
    "src" = "https://github.com/pivotal/credhub-release.git#${CREDHUB_RELEASE_VERSION}:src/credhub"
    "files" = "files"
  }
}
