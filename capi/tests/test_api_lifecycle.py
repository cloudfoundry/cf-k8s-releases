"""Render API lifecycle contracts. Requires helm and Mike Farah's yq v4."""

import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


CHART = Path(__file__).resolve().parents[1] / "helm"
VALUES = {
    "cloudController": {
        "enabled": True,
        "certificateSecrets": {
            key: "test-placeholder"
            for key in (
                "mutualTLS", "loggregatorTLS", "logcacheTLS", "uaaCA",
                "credhubCA", "publicTLS", "promScraperTLS",
            )
        },
        "config": {
            "dbEncryptionKey": "test-placeholder",
            "stagingUploadUser": "test-placeholder",
            "stagingUploadPassword": "test-placeholder",
            **{
                key: {"connectionConfig": {"awsSecretAccessKey": "test-placeholder"}}
                for key in ("droplets", "packages", "buildpacks", "resourcePool")
            },
        },
    },
    "ccUploader": {
        "certificateSecrets": {"ccClient": "test-placeholder", "server": "test-placeholder"}
    },
    "routeRegistrar": {"certificateSecret": "test-placeholder"},
    "ccdb": {"password": "test-placeholder"},
    "oauthClientsSecret": "test-placeholder",
}


class ApiLifecycleTest(unittest.TestCase):
    def render(self, *settings, succeeds=True, values_file=None):
        with tempfile.TemporaryDirectory() as directory:
            values = Path(directory) / "values.json"
            values.write_text(json.dumps(VALUES))
            command = [
                "helm", "template", "test", str(CHART), "-f", str(values),
            ]
            if values_file is not None:
                command.extend(["-f", str(values_file)])
            for setting in settings:
                command.extend(["--set", setting])
            result = subprocess.run(command, capture_output=True, text=True)
        if not succeeds:
            self.assertNotEqual(
                result.returncode, 0,
                f"Expected helm template to reject settings={settings!r} "
            )
            return result.stderr
        self.assertEqual(result.returncode, 0, result.stderr)
        converted = subprocess.run(
            ["yq", "-o=json", "-I=0", "."], input=result.stdout,
            capture_output=True, text=True, check=True,
        )
        return [json.loads(line) for line in converted.stdout.splitlines() if line]

    @staticmethod
    def resource(documents, kind, name):
        return next(d for d in documents if d and d["kind"] == kind and d["metadata"]["name"] == name)

    def test_shutdown_order_and_phase_budgets(self):
        for count, nginx_seconds, worker_seconds in [(0, 30, 300), (3, 7, 11)]:
            with self.subTest(workers=count):
                documents = self.render(
                    f"cloudController.config.jobs.local.numberOfWorkers={count}",
                    f"cloudController.config.nginxDrainTimeout={nginx_seconds}",
                    f"cloudController.config.jobs.local.localWorkerGracePeriodSeconds={worker_seconds}",
                    "cloudController.config.promMetricsServerEnabled=true",
                )
                template = self.resource(documents, "Deployment", "cloud-controller")["spec"]["template"]
                pod = template["spec"]
                init = pod["initContainers"]
                self.assertEqual(
                    [c["name"] for c in init],
                    ["set-pod-identity", "valkey"]
                    + [f"local-worker-{i + 1}" for i in range(count)] + ["cloud-controller"],
                )
                for sidecar in init[1:]:
                    self.assertEqual(sidecar["restartPolicy"], "Always")
                self.assertEqual(pod["terminationGracePeriodSeconds"], nginx_seconds + 20 + worker_seconds)
                for sidecar in init[2:]:
                    seconds = 20 if sidecar["name"] == "cloud-controller" else worker_seconds
                    self.assertEqual(sidecar["command"][:5], [
                        "timeout", "--foreground", "--preserve-status", f"--kill-after={seconds}s", "0",
                    ])


    def test_global_worker_cleanup(self):
        for threads in [0, 3]:
            with self.subTest(threads=threads):
                documents = self.render(
                    f"cloudController.config.jobs.generic.numberOfWorkerThreads={threads}",
                    "cloudController.config.jobs.generic.workerGracePeriodSeconds=3",
                    "ccWorker.cleanup.timeoutSeconds=7",
                )
                template = self.resource(documents, "Deployment", "cc-worker")["spec"]["template"]
                self.assertIn("checksum/cc-worker-cleanup-config", template["metadata"]["annotations"])
                pod = template["spec"]
                self.assertEqual(pod["terminationGracePeriodSeconds"], 11)
                self.assertEqual([c["name"] for c in pod["initContainers"]], ["set-pod-identity", "cc-worker-cleanup"])
                cleanup = pod["initContainers"][-1]
                worker = pod["containers"][0]
                self.assertEqual(cleanup["restartPolicy"], "Always")
                self.assertNotIn("preStop", cleanup.get("lifecycle", {}))
                self.assertNotIn("startupProbe", cleanup)
                self.assertNotIn("livenessProbe", cleanup)
                self.assertEqual(cleanup["image"], worker["image"])
                self.assertEqual(cleanup["envFrom"], worker["envFrom"])
                environment = {item["name"]: item for item in cleanup["env"]}
                self.assertEqual(environment["WORKER_NAME"]["value"], "cc_global_worker.cc-worker.$(POD_UID).1")
                self.assertEqual(environment["WORKER_THREADS"]["value"], str(threads))
                self.assertEqual(environment["CLEANUP_TIMEOUT_SECONDS"]["value"], "7")
                self.assertEqual(environment["CLOUD_CONTROLLER_NG_CONFIG"]["value"], "/tmp/config.yaml")
                self.assertEqual(worker["command"][:5], ["timeout", "--foreground", "--preserve-status", "--kill-after=3s", "0"])
                task = "jobs:generic[cc_global_worker.cc-worker.$(POD_UID).1" + (",3,2" if threads else "") + "]"
                self.assertEqual(worker["command"][-1], task)
                self.assertEqual(cleanup["volumeMounts"][:-1], worker["volumeMounts"])
                source = self.resource(documents, "ConfigMap", "cc-worker-cleanup-config")["data"]["cleanup.rb"]
                self.assertEqual(source, (CHART / "files" / "cc-worker-cleanup.rb").read_text().rstrip())

    def test_uploader_drain_timeout_reaches_process(self):
        for minutes in [5, 15, 20]:
            with self.subTest(minutes=minutes):
                settings = [] if minutes == 15 else [f"ccUploader.config.ccUploaderDrainTimeoutInMinutes={minutes}"]
                documents = self.render(*settings)
                pod = self.resource(documents, "Deployment", "cc-uploader")["spec"]["template"]["spec"]
                uploader = pod["containers"][0]
                self.assertNotIn("command", uploader)
                self.assertEqual(uploader["args"], [
                    "--configPath=/cc-uploader/cc-uploader.json",
                    f"--shutdownTimeoutInMinutes={minutes}",
                ])
                self.assertEqual(pod["terminationGracePeriodSeconds"], minutes * 60 + 1)

    def test_pod_identity_is_shared_without_statefulset_ordinals(self):
        documents = self.render("cloudController.config.jobs.local.numberOfWorkers=3")
        self.assertFalse(any(d and d["kind"] == "StatefulSet" for d in documents))
        self.assertNotIn("apps.kubernetes.io/pod-index", json.dumps(documents))
        for name, role in [("cloud-controller", "api"), ("cc-worker", "cc-worker")]:
            with self.subTest(workload=name):
                pod = self.resource(documents, "Deployment", name)["spec"]["template"]["spec"]
                initializer = pod["initContainers"][0]
                self.assertEqual(initializer["env"], [{
                    "name": "POD_UID",
                    "valueFrom": {"fieldRef": {"fieldPath": "metadata.uid"}},
                }])
                self.assertIn(f'.name = "{role}-" + strenv(POD_UID)', initializer["command"][-1])
                identities = [
                    c for c in pod["initContainers"] + pod["containers"]
                    if c["name"].startswith("local-worker-")
                    or c["name"] in ("cc-worker", "cc-worker-cleanup")
                ]
                for container in identities:
                    environment = {item["name"]: item for item in container["env"]}
                    self.assertEqual(environment["POD_UID"], initializer["env"][0])
                    if container["name"] == "cc-worker":
                        self.assertEqual(environment["INDEX"]["value"], "1")
                    else:
                        self.assertNotIn("INDEX", environment)
                    if container["name"].startswith("local-worker-"):
                        ordinal = container["name"].removeprefix("local-worker-")
                        self.assertEqual(
                            container["command"][-1],
                            f"jobs:local[cc_api_worker.api.$(POD_UID).{ordinal}]",
                        )

    def test_initializer_keeps_numeric_index_and_isolates_local_queues(self):
        documents = self.render()
        # Execute the rendered yq expression with local paths, not a Kubernetes pod.
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "source.yaml"
            output = Path(directory) / "config.yaml"
            config.write_text('index: 42\nname: "old"\nother: unchanged\n')
            for name, role in [("cloud-controller", "api"), ("cc-worker", "cc-worker")]:
                with self.subTest(workload=name):
                    pod = self.resource(documents, "Deployment", name)["spec"]["template"]["spec"]
                    script = pod["initContainers"][0]["command"][-1]
                    script = script.replace("/etc/cloud-controller/config.yaml", shlex.quote(str(config)))
                    script = script.replace("/tmp/config.yaml", shlex.quote(str(output)))
                    queues = []
                    for uid in [
                        "00000000-0000-0000-0000-000000000001",
                        "00000000-0000-0000-0000-000000000002",
                        "00000000-0000-0000-0000-000000000001",
                    ]:
                        environment = {**os.environ, "POD_UID": uid}
                        subprocess.run(["sh", "-c", script], env=environment, check=True, capture_output=True)
                        result = subprocess.run(
                            ["yq", "-o=json", ".", str(output)],
                            check=True, capture_output=True, text=True,
                        )
                        initialized = json.loads(result.stdout)
                        self.assertEqual(initialized, {"index": 0, "name": f"{role}-{uid}", "other": "unchanged"})
                        # Pinned CAPI Jobs::Queues.local interpolates name and integer index.
                        queues.append(f"cc-{initialized['name']}-{initialized['index']}")
                    self.assertNotEqual(queues[0], queues[1])
                    self.assertEqual(queues[0], queues[2])
                    for uid in [None, ""]:
                        environment = {key: value for key, value in os.environ.items() if key != "POD_UID"}
                        if uid is not None:
                            environment["POD_UID"] = uid
                        result = subprocess.run(["sh", "-c", script], env=environment, capture_output=True, text=True)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn("POD_UID is required", result.stderr)

    def test_rollout_defaults_and_independent_overrides(self):
        documents = self.render()
        for name in ["cloud-controller", "cc-worker"]:
            spec = self.resource(documents, "Deployment", name)["spec"]
            self.assertEqual(spec["strategy"], {
                "type": "RollingUpdate",
                "rollingUpdate": {"maxSurge": 1, "maxUnavailable": 0},
            })
        documents = self.render(
            "cloudController.replicas=4", "ccWorker.replicas=3",
            "cloudController.rollingUpdate.maxSurge=2", "cloudController.rollingUpdate.maxUnavailable=1",
            "ccWorker.rollingUpdate.maxSurge=50%", "ccWorker.rollingUpdate.maxUnavailable=25%",
        )
        for name, replicas, surge, unavailable in [
            ("cloud-controller", 4, 2, 1), ("cc-worker", 3, "50%", "25%"),
        ]:
            spec = self.resource(documents, "Deployment", name)["spec"]
            self.assertEqual(spec["replicas"], replicas)
            self.assertEqual(spec["strategy"]["rollingUpdate"], {"maxSurge": surge, "maxUnavailable": unavailable})

    def test_kind_rollout_values_render(self):
        documents = self.render(values_file=CHART.parent / "tests/kind-rollout-values.yaml")
        for name, replicas in [("cloud-controller", 4), ("cc-worker", 3)]:
            spec = self.resource(documents, "Deployment", name)["spec"]
            self.assertEqual(spec["replicas"], replicas)
            self.assertEqual(spec["strategy"]["rollingUpdate"], {"maxSurge": 2, "maxUnavailable": 0})

    def test_invalid_rollout_budgets_are_rejected(self):
        for component in ["cloudController", "ccWorker"]:
            for field in ["maxSurge", "maxUnavailable"]:
                for value in ["-1", "101%", "-1%", "1.5", "true", "many", "null"]:
                    with self.subTest(component=component, field=field, value=value):
                        self.render(f"{component}.rollingUpdate.{field}={value}", succeeds=False)
            for surge, unavailable in [("0", "0"), ("0%", "0%"), ("0", "0%"), ("0%", "0"), ("0", "1%")]:
                with self.subTest(component=component, surge=surge, unavailable=unavailable):
                    error = self.render(
                        f"{component}.replicas=3",
                        f"{component}.rollingUpdate.maxSurge={surge}",
                        f"{component}.rollingUpdate.maxUnavailable={unavailable}",
                        succeeds=False,
                    )
                    self.assertIn(f"{component}.rollingUpdate", error)
            self.render(f"{component}.replicas=3", f"{component}.rollingUpdate.maxSurge=1%")
            self.render(f"{component}.rollingUpdate.maxSurge=0", f"{component}.rollingUpdate.maxUnavailable=1")
            self.render(f"{component}.replicas=0")
            self.render(f"{component}.replicas=0", f"{component}.rollingUpdate.maxSurge=1%")
            self.render(
                f"{component}.replicas=0", f"{component}.rollingUpdate.maxSurge=0%",
                f"{component}.rollingUpdate.maxUnavailable=0%", succeeds=False,
            )

    def test_readiness_uses_api_health_and_worker_initialization(self):
        documents = self.render(
            "cloudController.config.publicTLS.port=19024",
            "cloudController.config.readinessPort.cloudControllerWorker=19025",
        )
        api = self.resource(documents, "Deployment", "cloud-controller")["spec"]["template"]["spec"]
        server = next(c for c in api["initContainers"] if c["name"] == "cloud-controller")
        self.assertEqual(server["readinessProbe"]["httpGet"], {"path": "/healthz", "port": 19024, "scheme": "HTTPS"})
        worker = self.resource(documents, "Deployment", "cc-worker")["spec"]["template"]["spec"]["containers"][0]
        self.assertEqual(worker["readinessProbe"]["tcpSocket"], {"port": 19025})
        config = self.resource(documents, "Secret", "cloud-controller-config")["stringData"]["config.yaml"]
        self.assertIn("cloud_controller_worker: 19025", config)
        for port in [-1, 0, 65536]:
            self.render(f"cloudController.config.readinessPort.cloudControllerWorker={port}", succeeds=False)
        worker = self.resource(self.render(), "Deployment", "cc-worker")["spec"]["template"]["spec"]["containers"][0]
        self.assertEqual(worker["readinessProbe"]["tcpSocket"], {"port": 9025})

    def test_migration_remains_a_separate_single_pod_hook(self):
        documents = self.render("cloudController.replicas=4", "ccWorker.replicas=3")
        migration = self.resource(documents, "Job", "capi-db-migration")
        self.assertEqual(migration["metadata"]["annotations"]["helm.sh/hook"], "pre-install,pre-upgrade")
        self.assertEqual(migration["spec"]["completions"], 1)
        self.assertEqual(migration["spec"]["parallelism"], 1)
        container = migration["spec"]["template"]["spec"]["containers"][0]
        self.assertEqual(container["command"], ["/usr/bin/setup-db.sh"])
        for name in ["cloud-controller", "cc-worker"]:
            workload = self.resource(documents, "Deployment", name)
            self.assertNotIn("setup-db.sh", json.dumps(workload))

    def test_disabled_api_has_no_workload(self):
        documents = self.render("cloudController.enabled=false")
        for name in ["cloud-controller", "cc-worker", "capi-db-migration"]:
            self.assertFalse(any(d and d.get("metadata", {}).get("name") == name for d in documents))


if __name__ == "__main__":
    unittest.main()
