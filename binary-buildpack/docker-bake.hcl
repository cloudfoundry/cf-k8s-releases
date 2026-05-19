variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/binary-buildpack
    default = "1.1.21"
}

group "default" {
    targets = [ "binary-buildpack" ]
}

target "binary-buildpack" {
    dockerfile = "../shared/buildpack.Dockerfile"
    tags = [ "${REGISTRY_PREFIX}binary-buildpack:${BUILDPACK_VERSION}" ]

    args = {
        NAME = "binary-buildpack"
        VERSION = BUILDPACK_VERSION
    }
}
