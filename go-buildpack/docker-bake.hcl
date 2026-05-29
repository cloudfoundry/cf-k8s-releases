variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
    # renovate: dataSource=github-releases depName=cloudfoundry/go-buildpack
    default = "1.10.24"
}

group "default" {
    targets = [ "go-buildpack" ]
}

target "go-buildpack" {
    tags = [ "${REGISTRY_PREFIX}go-buildpack:${BUILDPACK_VERSION}" ]

    contexts = {
      "src" = "https://github.com/cloudfoundry/go-buildpack.git#v${BUILDPACK_VERSION}"
      "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
    }
}
