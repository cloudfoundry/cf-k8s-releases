variable "REGISTRY_PREFIX" {
    default = ""
}

variable "BUILDPACK_VERSION" {
    # renovate: dataSource=github-releases depName=cloudfoundry/dotnet-core
    default = "2.4.29"
}

group "default" {
    targets = [ "dotnet-core-buildpack" ]
}

target "dotnet-core-buildpack" {
    tags = [ "${REGISTRY_PREFIX}dotnet-core-buildpack:${BUILDPACK_VERSION}" ]

    contexts = {
      "src" = "https://github.com/cloudfoundry/dotnet-core-buildpack.git#v${BUILDPACK_VERSION}"
      "libbuildpack" = "https://github.com/cloudfoundry/libbuildpack.git"
    }
}
