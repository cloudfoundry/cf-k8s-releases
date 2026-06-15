variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
    # renovate: dataSource=github-releases depName=cloudfoundry/php-buildpack
    default = "5.0.6"
}

group "default" {
    targets = [ "php-buildpack" ]
}

target "php-buildpack" {
    tags = [ "${REGISTRY_PREFIX}php-buildpack:${BUILDPACK_VERSION}", "${REGISTRY_PREFIX}php-buildpack:latest" ]

    contexts = {
      "src" = "https://github.com/cloudfoundry/php-buildpack.git#v${BUILDPACK_VERSION}"
      "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
    }
}
