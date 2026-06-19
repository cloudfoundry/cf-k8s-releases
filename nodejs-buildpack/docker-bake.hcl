variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
    # renovate: dataSource=github-releases depName=cloudfoundry/nodejs-buildpack
    default = "1.9.2"
}

group "default" {
    targets = [ "nodejs-buildpack" ]
}

target "nodejs-buildpack" {
    tags = [ "${REGISTRY_PREFIX}nodejs-buildpack:${BUILDPACK_VERSION}", "${REGISTRY_PREFIX}nodejs-buildpack:latest" ]
    dockerfile = "../buildpacks.Dockerfile"

    args = {
        BUILDPACK_VERSION = BUILDPACK_VERSION
    }

    contexts = {
      "src" = "https://github.com/cloudfoundry/nodejs-buildpack.git#v${BUILDPACK_VERSION}"
      "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
    }
}
