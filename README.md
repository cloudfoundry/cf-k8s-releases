# cf-k8s-releases

This repository contains the assets to install the common components of cloud foundry on kubernetes.

Those assets are used when installing it on `kind` (see [kind-deployment](https://github.com/cloudfoundry/kind-deployment))

The kubernetes specific components can be found here:
- [k8s-garden-client](https://github.com/cloudfoundry/k8s-garden-client)
- [k8s-policy-agent](https://github.com/cloudfoundry/k8s-policy-agent)

## Helm Charts

The helm charts can be found in the `helm` folder of the releases that have one.

They are published to ghcr.io/cloudfoundry/helm.

## Images

For building the images of a release, run `docker buildx bake` in that folder.

The images are published to ghcr.io/cloudfoundry/k8s.

## Read More Documentation

- [Local Development Guide](docs/local-development-guide.md)

## Contributing

Please check our [contributing guidelines](/CONTRIBUTING.md).

This project follows [Cloud Foundry Code of Conduct](https://www.cloudfoundry.org/code-of-conduct/).
