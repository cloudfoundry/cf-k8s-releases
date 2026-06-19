variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
    # renovate: dataSource=github-releases depName=cloudfoundry/staticfile-buildpack
    default = "1.6.38"
}

group "default" {
    targets = [ "staticfile-buildpack" ]
}

target "staticfile-buildpack" {
    tags = [ "${REGISTRY_PREFIX}staticfile-buildpack:${BUILDPACK_VERSION}", "${REGISTRY_PREFIX}staticfile-buildpack:latest" ]
    dockerfile = "../buildpacks.Dockerfile"

    args = {
        BUILDPACK_VERSION = BUILDPACK_VERSION
    }

    contexts = {
      "src" = "https://github.com/cloudfoundry/staticfile-buildpack.git#v${BUILDPACK_VERSION}"
      "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
    }
}
