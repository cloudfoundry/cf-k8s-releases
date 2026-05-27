variable "REGISTRY_PREFIX" {
  default = ""
}

variable "NFS_VOLUME_RELEASE_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/nfs-volume-release
  default = "7.53.0"
}

group "default" {
  targets = ["nfs-volume"]
}

target "nfs-volume" {
  dockerfile = "${component}.Dockerfile"
  tags = [ "${REGISTRY_PREFIX}${component}:latest", "${REGISTRY_PREFIX}${component}:${NFS_VOLUME_RELEASE_VERSION}" ]
  name = component

  matrix = {
    "component" = [ "nfsv3driver", "nfsbroker" ]
  }

  contexts = {
    "src" = "https://github.com/cloudfoundry/nfs-volume-release.git#v${NFS_VOLUME_RELEASE_VERSION}:src"
  }
}
