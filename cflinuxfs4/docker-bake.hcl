variable "REGISTRY_PREFIX" {
  default = ""
}

variable "CFLINUXFS4_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/cflinuxfs4-release
  default = "1.321.0"
}

group "default" {
  targets = ["cflinuxfs4"]
}

target "cflinuxfs4" {
  dockerfile = "cflinuxfs4.Dockerfile"
  tags = [ "${REGISTRY_PREFIX}cflinuxfs4:${CFLINUXFS4_VERSION}" ]

  args = {
    "CFLINUXFS4_VERSION" = CFLINUXFS4_VERSION
  }
}
