"""Render API lifecycle contracts. Requires helm and Mike Farah's yq v4."""

import json
from pathlib import Path
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
    def render(self, *settings, succeeds=True):
        with tempfile.TemporaryDirectory() as directory:
            values = Path(directory) / "values.json"
            values.write_text(json.dumps(VALUES))
            command = [
                "helm", "template", "test", str(CHART), "-f", str(values),
            ]
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
                template = self.resource(documents, "StatefulSet", "cloud-controller")["spec"]["template"]
                pod = template["spec"]
                init = pod["initContainers"]
                self.assertEqual(
                    [c["name"] for c in init],
                    ["set-name-index", "valkey"]
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
                template = self.resource(documents, "StatefulSet", "cc-worker")["spec"]["template"]
                self.assertIn("checksum/cc-worker-cleanup-config", template["metadata"]["annotations"])
                pod = template["spec"]
                self.assertEqual(pod["terminationGracePeriodSeconds"], 11)
                self.assertEqual([c["name"] for c in pod["initContainers"]], ["set-name-index", "cc-worker-cleanup"])
                cleanup = pod["initContainers"][-1]
                worker = pod["containers"][0]
                self.assertEqual(cleanup["restartPolicy"], "Always")
                self.assertNotIn("preStop", cleanup.get("lifecycle", {}))
                self.assertNotIn("startupProbe", cleanup)
                self.assertNotIn("livenessProbe", cleanup)
                self.assertEqual(cleanup["image"], worker["image"])
                self.assertEqual(cleanup["envFrom"], worker["envFrom"])
                environment = {item["name"]: item for item in cleanup["env"]}
                self.assertEqual(environment["WORKER_NAME"]["value"], "cc_global_worker.cc-worker.$(INDEX).1")
                self.assertEqual(environment["WORKER_THREADS"]["value"], str(threads))
                self.assertEqual(environment["CLEANUP_TIMEOUT_SECONDS"]["value"], "7")
                self.assertEqual(environment["CLOUD_CONTROLLER_NG_CONFIG"]["value"], "/tmp/config.yaml")
                self.assertEqual(worker["command"][:5], ["timeout", "--foreground", "--preserve-status", "--kill-after=3s", "0"])
                task = "jobs:generic[cc_global_worker.cc-worker.$(INDEX).1" + (",3,2" if threads else "") + "]"
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

    def test_disabled_api_has_no_workload(self):
        documents = self.render("cloudController.enabled=false")
        self.assertFalse(any(d and d.get("metadata", {}).get("name") == "cloud-controller" for d in documents))


if __name__ == "__main__":
    unittest.main()
