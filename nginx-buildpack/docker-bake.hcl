variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
    # renovate: dataSource=github-releases depName=cloudfoundry/nginx-buildpack
    default = "1.2.17"
}

group "default" {
    targets = [ "nginx-buildpack" ]
}

target "nginx-buildpack" {
    tags = [ "${REGISTRY_PREFIX}nginx-buildpack:${BUILDPACK_VERSION}" ]

    contexts = {
      "src" = "https://github.com/cloudfoundry/nginx-buildpack.git#v${BUILDPACK_VERSION}"
      "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
    }
}
