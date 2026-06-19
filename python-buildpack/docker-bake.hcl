variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
    # renovate: dataSource=github-releases depName=cloudfoundry/python-buildpack
    default = "1.9.1"
}

group "default" {
    targets = [ "python-buildpack" ]
}

target "python-buildpack" {
    tags = [ "${REGISTRY_PREFIX}python-buildpack:${BUILDPACK_VERSION}", "${REGISTRY_PREFIX}python-buildpack:latest" ]
    dockerfile = "../buildpacks.Dockerfile"

    args = {
        BUILDPACK_VERSION = BUILDPACK_VERSION
    }

    contexts = {
      "src" = "https://github.com/cloudfoundry/python-buildpack.git#v${BUILDPACK_VERSION}"
      "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
    }
}
