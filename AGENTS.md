# AGENTS.md

Guidance for humans and AI agents working in `cf-k8s-releases`. For contribution process
(PR scope, raising issues, code of conduct) see [`CONTRIBUTING.md`](CONTRIBUTING.md); this
file covers how the repo is built and how to work in it effectively.

## What this repo is

`cf-k8s-releases` provides the assets to run the common components of Cloud Foundry on
Kubernetes. For each upstream Cloud Foundry **BOSH release** it:

- builds **OCI container images from that release's source code** (fetched from the
  upstream Git repo at a pinned tag), and
- for most releases, provides a **hand-written Helm chart** to deploy it.

Images are published to `ghcr.io/cloudfoundry/k8s`, Helm charts to
`ghcr.io/cloudfoundry/helm`. The output is consumed by
[`kind-deployment`](https://github.com/cloudfoundry/kind-deployment); the
Kubernetes-specific pieces live in `k8s-garden-client` and `k8s-policy-agent`.

Two things to be clear about up front:

- **The Helm charts are authored and maintained by hand in this repo** — they are not
  generated or derived from the BOSH release. Keeping a chart in step with its upstream
  release is manual work.
- **This repo contains no source code.** It holds only build definitions
  (`docker-bake.hcl`, Dockerfiles), the hand-written charts, and CI workflows. Everything
  compiled into an image is fetched from upstream at build time.

## Layout

Each top-level directory maps to one upstream release — almost always a BOSH release. A
few directories package buildpacks or stacks instead; those are not BOSH releases and
have **no Helm chart**.

A directory typically contains:

- `docker-bake.hcl` — the image build definition,
- one or more `*.Dockerfile`,
- `helm/` — the chart (`Chart.yaml`, `values.yaml`, `values.schema.json`, `templates/`),
  present only for releases that ship one.

Buildpack and stack directories are the exception: no `helm/`, and no Dockerfile of their
own — they share a root-level `buildpacks.Dockerfile` / `stacks.Dockerfile`.

The whole build system is these per-directory bake files plus the GitHub Actions
workflows; there is no top-level Makefile or task runner.

## Building images (`docker-bake.hcl`)

Each bake file:

- declares a `REGISTRY_PREFIX` variable (empty locally; CI sets `ghcr.io/cloudfoundry/k8s/`),
- declares the upstream version in a variable carrying a Renovate marker (see below),
- pulls the upstream source at that version through a git build context
  (`contexts.src = "https://github.com/.../<repo>.git#<ref>:<subdir>"`) — source is never
  vendored into this repo,
- defines a `group "default"` (what bare `docker buildx bake` builds) and one or more
  targets. A target may use a `matrix` to produce several images from one source.

Dockerfiles are multi-stage: build from the `src` context, then copy the result into a
runtime base. The runtime base varies by what the process needs — don't assume one.

## Helm charts (`helm/`)

Charts are hand-written. Conventions you'll see across them:

- each image is referenced as `image.repository` / `image.tag` / `image.imagePullPolicy`;
  leaving `image.tag` empty makes the template fall back to the chart's `appVersion`, so
  the chart and its images stay version-locked,
- `values.schema.json` is a JSON Schema with `additionalProperties: false`, enforced at
  template/install time — so `values.yaml` and `values.schema.json` must be edited
  together.

## Configuration: mapping to the upstream BOSH job

A chart is a hand-written port of the release's BOSH jobs, and the mapping is consistent:

- **Each BOSH job → a workload + a config object in `templates/`.** You'll usually find a
  `<process>.yaml` (the Deployment / DaemonSet / StatefulSet) and a `<process>-config.yaml`
  (a ConfigMap, or a Secret when it carries credentials) holding that process's config
  file(s) — the equivalent of the job's ERB-rendered templates.
- **Job properties → chart values.** A BOSH property becomes an entry in `values.yaml`
  (declared in `values.schema.json`), wired into the config object with `{{ .Values.* }}`.

The config file itself is written one of two ways:

- **inline** in the `<process>-config.yaml` template, with `{{ .Values.* }}` interpolation; or
- as a static file under `helm/files/`, pulled in with `tpl (.Files.Get "files/<name>") .`
  so the `{{ ... }}` inside it resolve at render time (larger config files tend to use this).

### Finding the upstream equivalent

The source of truth for what a process needs is the **upstream BOSH release repo at the
pinned version**, not this repo. Identify it from the directory's `docker-bake.hcl`
(`contexts.src` gives the repo and ref) and `Chart.yaml`'s `appVersion`. In that repo, at
that tag, look under:

- `jobs/<job>/spec` — the property list, defaults, and consumed/provided links;
- `jobs/<job>/templates/*.erb` — how the config file is rendered.

Note the images build from the release's `src/` subtree, but the job config lives in its
`jobs/` subtree — same repo and tag, different path.

### Updating configuration

1. Locate the process's config object (`templates/<process>-config.yaml`, plus any
   `helm/files/*` it reads).
2. Check the upstream `jobs/<job>/spec` and `templates/*.erb` at the pinned tag for the real
   property name, default, and shape before changing anything.
3. Make the change: a new tunable → add it to `values.yaml` **and** `values.schema.json`,
   then reference it in the config; a fixed value → inline it.
4. Validate with `helm lint ./helm` and `helm template ./helm` (optionally `--set` the new
   value).
5. Config/template edits alone publish nothing — cutting a release needs a `Chart.yaml`
   version bump (see Sharp edges).

## Versioning & Renovate

Config: `.github/renovate.json`. Bumps are driven by a custom regex manager, not the stock
Helm/Docker managers (`helm-values` is disabled).

- Marker, placed immediately above the value line:
  `# renovate: dataSource=<ds> depName=<org>/<repo> [packageName=<pkg>]`, then
  `key: "value"` (YAML) or `key = "value"` (HCL). It must be adjacent to the value or it
  won't bump.
- Markers are honored in `helm/Chart.yaml`, `helm/values.yaml`, `docker-bake.hcl`, the
  workflow files, and `.github/actions/init`.
- `cloudfoundry/*` and `pivotal/*` minor/patch bumps **automerge** (concurrency and hourly
  PR limits are unlimited), so a bump can land on `main` and fire a release unattended.
- In `Chart.yaml`, `appVersion` tracks the upstream release (and becomes the default image
  tag); `version` is the chart's own version (the Helm OCI tag). The two need not be equal.

## CI/CD

Each release directory has its own hand-written pair — `<dir>-release.yaml` and
`<dir>-verify.yaml` — plus one shared `reusable-matrix-image-build.yaml`. They are
copy-paste siblings, **not generated**: a cross-cutting change must be applied to every
pair. `.github/actions/init` is the shared bootstrap (checks out `kind-deployment`, sets
up buildx/QEMU/Go/Helm/kind/cf CLI, logs into ghcr.io).

**Release** — on push to `main`, gated to that directory's watched path, and idempotent
(skips if the version already exists in the registry). It builds the directory's image(s)
— either via the shared multi-arch matrix workflow or an inline `bake --push` — and, if the
release ships a chart, packages and `helm push`es it.

**Verify** — on PRs, gated by `dorny/paths-filter` on the directory's paths. For a release
with a chart it builds images, stands up a real KinD cluster, and `helmfile sync`s the
chart against `kind-deployment` — a full deploy test, not just a build. Chartless
directories only build (`bake --load`).

## Local development

```bash
# build a directory's default targets (run inside the directory)
docker buildx bake

# build one image from LOCAL source instead of the pinned upstream tag
docker buildx bake <image> --set <image>.contexts.src=<path-to-local-source>

# list buildable images
docker buildx bake --print

# package & publish a chart (what release CI does)
helm package ./helm && helm push <name>-*.tgz oci://ghcr.io/cloudfoundry/helm
```

Podman: `docker-bake.hcl` is not supported — build manually with `podman build` and a
`--build-context src=...` (see `docs/local-development-guide.md`).

## Adding a new release

1. Create the directory with a `docker-bake.hcl` (`REGISTRY_PREFIX` var, a Renovate-marked
   version var, `group "default"`, targets, `contexts.src` git URL).
2. Add the `*.Dockerfile`(s) — copy the multi-stage pattern from a similar sibling.
3. If the release ships a chart, add `helm/` (`Chart.yaml` with Renovate-marked `version`
   and `appVersion`, `values.yaml`, `values.schema.json`, `templates/`).
4. Copy both workflow files from a similar sibling and rename the directory / targets /
   path filters. Nothing auto-discovers a new directory.

## Sharp edges

- A release fires **only** on its one watched path (`helm/Chart.yaml` for chart releases,
  `docker-bake.hcl` for image-only ones). Editing a Dockerfile, template, or `values.yaml`
  without bumping that version publishes nothing on push to `main`.
- `values.yaml` and `values.schema.json` must change together — `additionalProperties: false`
  rejects any undeclared key.
- The upstream tag ref form is not uniform across directories (e.g. `#v${VERSION}` vs
  `#${VERSION}`). Copy the existing pattern for that directory; don't assume.
- Because charts are hand-maintained, publishing a new image / buildpack / stack version
  does **not** reach a chart that references it until you update that chart yourself. A
  chart may also reference images built by another directory, pinned explicitly.
- Workflows that bake from a shared parent-directory Dockerfile or remote contexts set
  `BUILDX_BAKE_ENTITLEMENTS_FS: "0"`; carry it over.
