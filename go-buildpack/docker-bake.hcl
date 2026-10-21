variable "REGISTRY_PREFIX" {
  default = ""
}

variable "BUILDPACK_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/go-buildpack
  default = "1.11.1"
}

variable "IMAGE_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/go-buildpack
  default = "1.11.1"
}

group "default" {
  targets = [ "go-buildpack" ]
}

target "go-buildpack" {
  tags = [ "${REGISTRY_PREFIX}go-buildpack:${IMAGE_VERSION}", "${REGISTRY_PREFIX}go-buildpack:latest" ]
  dockerfile = "../buildpacks.Dockerfile"

  args = {
    BUILDPACK_VERSION = BUILDPACK_VERSION
  }

  contexts = {
    "src" = "https://github.com/cloudfoundry/go-buildpack.git#v${BUILDPACK_VERSION}"
    "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
  }
}
