variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
    # renovate: dataSource=github-releases depName=cloudfoundry/nginx-buildpack
    default = "1.2.39"
}

group "default" {
    targets = [ "nginx-buildpack" ]
}

target "nginx-buildpack" {
    tags = [ "${REGISTRY_PREFIX}nginx-buildpack:${BUILDPACK_VERSION}", "${REGISTRY_PREFIX}nginx-buildpack:latest" ]
    dockerfile = "../buildpacks.Dockerfile"

    args = {
        BUILDPACK_VERSION = BUILDPACK_VERSION
    }

    contexts = {
      "src" = "https://github.com/cloudfoundry/nginx-buildpack.git#v${BUILDPACK_VERSION}"
      "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
    }
}
