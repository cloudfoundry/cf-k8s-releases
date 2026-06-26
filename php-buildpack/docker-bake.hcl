variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
    # renovate: dataSource=github-releases depName=cloudfoundry/php-buildpack
    default = "5.0.5"
}

group "default" {
    targets = [ "php-buildpack" ]
}

target "php-buildpack" {
    tags = [ "${REGISTRY_PREFIX}php-buildpack:${BUILDPACK_VERSION}", "${REGISTRY_PREFIX}php-buildpack:latest" ]
    dockerfile = "../buildpacks.Dockerfile"

    args = {
        BUILDPACK_VERSION = BUILDPACK_VERSION
    }

    contexts = {
      "src" = "https://github.com/cloudfoundry/php-buildpack.git#v${BUILDPACK_VERSION}"
      "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
    }
}
