variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
    # renovate: dataSource=github-releases depName=cloudfoundry/ruby-buildpack
    default = "1.10.15"
}

group "default" {
    targets = [ "ruby-buildpack" ]
}

target "ruby-buildpack" {
    tags = [ "${REGISTRY_PREFIX}ruby-buildpack:${BUILDPACK_VERSION}" ]

    contexts = {
      "src" = "https://github.com/cloudfoundry/ruby-buildpack.git#v${BUILDPACK_VERSION}"
      "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
    }
}
