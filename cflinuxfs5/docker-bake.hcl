variable "REGISTRY_PREFIX" {
  default = ""
}

variable "CFLINUXFS5_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/cflinuxfs5-release
  default = "0.43.0"
}

group "default" {
  targets = ["cflinuxfs5"]
}

target "cflinuxfs5" {
  dockerfile = "../stacks.Dockerfile"
  tags = [ "${REGISTRY_PREFIX}cflinuxfs5:${CFLINUXFS5_VERSION}", "${REGISTRY_PREFIX}cflinuxfs5:latest" ]

  args = {
    "STACK_VERSION" = CFLINUXFS5_VERSION
    "STACK_NAME" = "cflinuxfs5"
  }
}
