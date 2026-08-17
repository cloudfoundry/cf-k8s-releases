variable "REGISTRY_PREFIX" {
    default = ""
}

variable "DIEGO_RELEASE_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/diego-release
    default = "2.145.0"
}

variable "DIEGO_RELEASE_FORK" {
    default = "https://github.com/sap-contributions/diego-release-fork.git#support-k8s-garden-client"
}

variable "K8S_GARDEN_CLIENT_VERSION" {
  # renovate: dataSource=github-releases depName=cloudfoundry/k8s-garden-client
    default = "0.6.6"
}

group "default" {
    targets = [ "diego", "fileserver", "rep" ]
}

function "targetname" {
    params = [component]
    result = length(split("/", component)) > 1 ? split("/", component)[1] : component
}

target "diego" {
    dockerfile = "Dockerfile"
    tags = [ "${REGISTRY_PREFIX}${targetname(component)}:${DIEGO_RELEASE_VERSION}", "${REGISTRY_PREFIX}${targetname(component)}:latest" ]
    name = targetname(component)
  
    matrix = {
        "component" = [ "auctioneer", "bbs", "locket", "route-emitter", "diego-ssh/ssh-proxy" ]
    }

    args = {
        "COMPONENT" = split("/", component)[0]
        "CMD_PKG" = targetname(component)
    }

    contexts = {
        "src" = "https://github.com/cloudfoundry/diego-release.git#v${DIEGO_RELEASE_VERSION}:src"
    }
}

target "fileserver" {
    dockerfile = "fileserver.Dockerfile"
    tags = [ "${REGISTRY_PREFIX}fileserver:${DIEGO_RELEASE_VERSION}", "${REGISTRY_PREFIX}fileserver:latest" ]

    contexts = {
        "src"    = "https://github.com/cloudfoundry/diego-release.git#v${DIEGO_RELEASE_VERSION}:src",
        "config" = "https://github.com/cloudfoundry/diego-release.git#v${DIEGO_RELEASE_VERSION}:config"
    }
}

target "rep" {
    dockerfile = "rep.Dockerfile"
    tags = [ "${REGISTRY_PREFIX}rep:${DIEGO_RELEASE_VERSION}", "${REGISTRY_PREFIX}rep:latest" ]

    contexts = {
        "src"     = "${DIEGO_RELEASE_FORK}:src",
        "watcher" = "https://github.com/cloudfoundry/k8s-garden-client.git#v${K8S_GARDEN_CLIENT_VERSION}"
    }
}
