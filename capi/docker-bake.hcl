variable "REGISTRY_PREFIX" {
    default = ""
}

variable "CAPI_RELEASE_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/capi-release
  default = "1.238.0"
}

group "default" {
    targets = [ "capi" ]
}

target "capi" {
  dockerfile = "${component}.Dockerfile"
  tags = [ "${REGISTRY_PREFIX}${component}:latest", "${REGISTRY_PREFIX}${component}:${CAPI_RELEASE_VERSION}"]
  name = component
  
  matrix = {
    "component" = [ "cloud-controller", "cc-uploader", "cc-nginx", "tps-watcher" ]
  }

  contexts = {
    "src" = "https://github.com/cloudfoundry/capi-release.git#${CAPI_RELEASE_VERSION}:src"
    "storage-cli" = "https://github.com/cloudfoundry/capi-release.git#${CAPI_RELEASE_VERSION}:packages/storage-cli"
  }
}
