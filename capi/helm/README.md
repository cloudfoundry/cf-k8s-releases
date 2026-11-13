# CAPI chart

Requires Kubernetes 1.29 or newer with the SidecarContainers feature enabled
(enabled by default since 1.29).
Overrides of the Cloud Controller and local-worker images must include GNU timeout, as the
default Cloud Controller image does.

## API startup and shutdown

The API Pod starts its configuration initializer, then Valkey, local workers,
and Cloud Controller as native sidecars (initContainers with restartPolicy:
Always). Valkey must answer a ping before workers start; Cloud Controller must
answer /healthz over its Unix socket before nginx and the route registrar start
as ordinary containers.

On Pod termination, Kubernetes waits for nginx and the route registrar to exit,
then stops Cloud Controller, local workers in reverse order, and finally Valkey.
This keeps the API available while nginx drains requests and keeps local workers
available until the API can no longer enqueue work.

The nginx image's SIGQUIT stop signal initiates graceful shutdown.
cloudController.config.nginxDrainTimeout bounds nginx's worker shutdown time
(default 30 seconds, matching BOSH's cc.nginx_drain_timeout). Cloud Controller
gets 20 seconds, matching the upstream drain helper. Each local worker gets
cloudController.config.jobs.local.localWorkerGracePeriodSeconds (default 300).

GNU timeout supervises the API and local workers. A runtime duration of 0 leaves
normal operation unlimited; after kubelet sends SIGTERM, --kill-after bounds
shutdown. --foreground forwards the signal to the Ruby process, leaving it
responsible for its own children. These containers intentionally have no
preStop hooks: kubelet may execute those hooks before waiting for their turn in
the sidecar shutdown sequence.

The Pod grace period is nginx drain + 20 seconds for the API + the number of local
workers multiplied by their grace period + 10 seconds of overhead. With defaults,
this is 660 seconds. Unlike BOSH, Kubernetes stops these worker containers
sequentially. Force deletion or exhaustion of the Pod deadline can still prevent
graceful shutdown. Independent container restarts do not trigger this Pod-wide
sequence.

## Global worker shutdown

The cc-worker Pod runs a native cc-worker-cleanup sidecar using the same Cloud
Controller image, database configuration, and certificates as the main worker.
It waits for SIGTERM; it does not use a preStop hook. During Pod termination,
Kubernetes sends that signal only after the main worker has fully stopped.
The sidecar has no startup or liveness probes that could send it SIGTERM during
normal worker operation.

The main worker uses GNU timeout to cap shutdown at
cloudController.config.jobs.generic.workerGracePeriodSeconds. The sidecar then
calls the upstream jobs:clear_pending_locks rake task in a loop for the worker's
base name and each configured thread owner (base name followed by ` thread:N`).
The environment loads once, and the cleanup timeout bounds the entire loop.
If one owner fails, cleanup logs the error and continues with the remaining owners.
If any owner failed, it reports success and failure counts and exits nonzero
after all attempts.
This releases only that worker's locks, including during scale-down.
It leaves job records and other workers' locks intact.

ccWorker.cleanup.timeoutSeconds bounds application boot and database cleanup
(default 30 seconds); failures and timeouts are logged and exit nonzero.

The global-worker Pod grace period is worker drain + cleanup + 10 seconds of
overhead (55 seconds by default). Worker-only restarts still rely on same-owner
job reclaim. Force deletion, node loss, or a database outage can prevent cleanup;
the queue's existing lock expiry remains the fallback in those cases.

Run the chart lifecycle regression checks with:

    python3 capi/tests/test_api_lifecycle.py

The checks require Helm and Mike Farah's yq v4.
Task-loop checks use local Ruby and Rake. Signal and timeout checks additionally
use Docker with stubbed Cloud Controller tasks:

    python3 capi/tests/test_worker_cleanup.py

Set CAPI_TEST_IMAGE=cloud-controller:latest to use a locally built image, as CI
does; otherwise these checks use the chart's Ruby base image.
