variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
    # renovate: dataSource=github-releases depName=cloudfoundry/python-buildpack
    default = "1.8.24"
}

group "default" {
    targets = [ "python-buildpack" ]
}

target "python-buildpack" {
    tags = [ "${REGISTRY_PREFIX}python-buildpack:${BUILDPACK_VERSION}" ]

    contexts = {
      "src" = "https://github.com/cloudfoundry/python-buildpack.git#v${BUILDPACK_VERSION}"
      "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
    }
}
