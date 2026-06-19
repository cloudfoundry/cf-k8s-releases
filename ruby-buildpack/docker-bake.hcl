variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
    # renovate: dataSource=github-releases depName=cloudfoundry/ruby-buildpack
    default = "1.11.1"
}

group "default" {
    targets = [ "ruby-buildpack" ]
}

target "ruby-buildpack" {
    tags = [ "${REGISTRY_PREFIX}ruby-buildpack:${BUILDPACK_VERSION}", "${REGISTRY_PREFIX}ruby-buildpack:latest" ]
    dockerfile = "../buildpacks.Dockerfile"

    args = {
        BUILDPACK_VERSION = BUILDPACK_VERSION
    }

    contexts = {
      "src" = "https://github.com/cloudfoundry/ruby-buildpack.git#v${BUILDPACK_VERSION}"
      "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
    }
}
