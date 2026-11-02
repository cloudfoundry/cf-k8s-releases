variable "REGISTRY_PREFIX" {
  default = ""
}

variable "BUILDPACK_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/r-buildpack
  default = "1.2.29"
}

variable "IMAGE_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/r-buildpack
  default = "1.2.29"
}

group "default" {
  targets = [ "r-buildpack" ]
}

target "r-buildpack" {
  tags = [ "${REGISTRY_PREFIX}r-buildpack:${IMAGE_VERSION}", "${REGISTRY_PREFIX}r-buildpack:latest" ]
  dockerfile = "../buildpacks.Dockerfile"

  args = {
    BUILDPACK_VERSION = BUILDPACK_VERSION
  }

  contexts = {
    "src" = "https://github.com/cloudfoundry/r-buildpack.git#v${BUILDPACK_VERSION}"
    "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
  }
}
