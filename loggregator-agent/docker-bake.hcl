variable "REGISTRY_PREFIX" {
  default = ""
}

variable "LOGGREGATOR_AGENT_RELEASE_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/loggregator-agent-release
  default = "8.3.31"
}

variable "IMAGE_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/loggregator-agent-release
  default = "8.3.32-1"
}

group "default" {
  targets = ["loggregator-agent"]
}

target "loggregator-agent" {
  dockerfile = "${component}.Dockerfile"
  tags = [ "${REGISTRY_PREFIX}${component}:latest", "${REGISTRY_PREFIX}${component}:${IMAGE_VERSION}"]
  name = component

  matrix = {
    "component" = [ "syslog-agent", "syslog-binding-cache", "loggregator-agent", "forwarder-agent", "udp-forwarder" ]
  }

  contexts = {
    "src" = "https://github.com/cloudfoundry/loggregator-agent-release.git#v${LOGGREGATOR_AGENT_RELEASE_VERSION}:src"
  }
}
