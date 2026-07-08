variable "REGISTRY_PREFIX" {
  default = ""
}

variable "LOG_CACHE_RELEASE_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/log-cache-release
  default = "3.2.12"
}

group "default" {
  targets = ["log-cache"]
}

target "log-cache" {
  dockerfile = "log-cache.Dockerfile"
  tags = [ "${REGISTRY_PREFIX}${component}:latest", "${REGISTRY_PREFIX}${component}:${LOG_CACHE_RELEASE_VERSION}"]
  name = component

  matrix = {
    "component" = [ "cf-auth-proxy", "gateway", "log-cache", "syslog-server" ]
  }

  args = {
    "component" = component
    "LOG_CACHE_RELEASE_VERSION" = LOG_CACHE_RELEASE_VERSION
  }

  contexts = {
    "src" = "https://github.com/cloudfoundry/log-cache-release.git#v${LOG_CACHE_RELEASE_VERSION}:src"
  }
}
