variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/java-buildpack
    default = "5.0.2"
}

group "default" {
    targets = [ "java-buildpack" ]
}

target "java-buildpack" {
    dockerfile = "../shared/buildpack.Dockerfile"
    tags = [ "${REGISTRY_PREFIX}java-buildpack:${BUILDPACK_VERSION}" ]

    args = {
        NAME = "java-buildpack"
        VERSION = BUILDPACK_VERSION
    }
}
