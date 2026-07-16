variable "REGISTRY_PREFIX" {
  default = ""
}

variable "CFLINUXFS4_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/cflinuxfs4-release
  default = "1.322.0"
}

group "default" {
  targets = ["cflinuxfs4"]
}

target "cflinuxfs4" {
  dockerfile = "../stacks.Dockerfile"
  tags = [ "${REGISTRY_PREFIX}cflinuxfs4:${CFLINUXFS4_VERSION}", "${REGISTRY_PREFIX}cflinuxfs4:latest" ]

  args = {
    "STACK_VERSION" = CFLINUXFS4_VERSION
    "STACK_NAME" = "cflinuxfs4"
  }
}
