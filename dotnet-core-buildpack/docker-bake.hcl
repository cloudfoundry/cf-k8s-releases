variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
    # renovate: dataSource=github-releases depName=cloudfoundry/dotnet-core-buildpack
    default = "2.4.51"
}

group "default" {
    targets = [ "dotnet-core-buildpack" ]
}

target "dotnet-core-buildpack" {
    tags = [ "${REGISTRY_PREFIX}dotnet-core-buildpack:${BUILDPACK_VERSION}", "${REGISTRY_PREFIX}dotnet-core-buildpack:latest" ]

    contexts = {
      "src" = "https://github.com/cloudfoundry/dotnet-core-buildpack.git#v${BUILDPACK_VERSION}"
      "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
    }
}
