# Local Development Guide

This guide explains how to build a image with your local source code.

## 1. Make Code Changes

Edit your source code locally in your project directory (e.g., routing-release or other relevant Cloud Foundry project).

## 2. Build Image

Build a Docker image with your local changes:

```bash
docker buildx bake <image> --set <image>.contexts.src=<path-to-local-source>
```

**Example:**

In the directory `routing`:

```bash
docker buildx bake gorouter --set gorouter.contexts.src=/Users/user/routing-release/src
```

This creates an image tagged as `<image>:latest` (e.g., `gorouter:latest`) in your local Docker daemon.

<details>

  <summary>View all available images</summary>

To see all buildable images:

  ```bash
  docker buildx bake --print
  ```

</details>

> **Podman:** Building via `docker-bake.hcl` is not yet supported with Podman. Build images manually using `podman build` with the Dockerfiles in `releases/`:
>
> ```bash
> podman build -f releases/<component>/Dockerfile -t <image>:latest \
>   --build-context src=<path-to-local-source> .
> ```
