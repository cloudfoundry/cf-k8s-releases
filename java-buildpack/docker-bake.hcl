variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/java-buildpack
    default = "5.0.4"
}

group "default" {
    targets = [ "java-buildpack" ]
}

target "java-buildpack" {
    tags = [ "${REGISTRY_PREFIX}java-buildpack:${BUILDPACK_VERSION}", "${REGISTRY_PREFIX}java-buildpack:latest" ]

  args = {
    BUILDPACK_VERSION = BUILDPACK_VERSION
  }

    contexts = {
      "src" = "https://github.com/cloudfoundry/java-buildpack.git#v${BUILDPACK_VERSION}"
      "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
    }
}
