variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/binary-buildpack
    default = "1.1.26"
}

group "default" {
    targets = [ "binary-buildpack" ]
}

target "binary-buildpack" {
    tags = [ "${REGISTRY_PREFIX}binary-buildpack:${BUILDPACK_VERSION}" ]

    contexts = {
      "src" = "https://github.com/cloudfoundry/binary-buildpack.git#v${BUILDPACK_VERSION}"
      "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
    }
}
