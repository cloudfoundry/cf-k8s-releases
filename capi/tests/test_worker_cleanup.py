"""Exercise the sidecar's signals and deadlines with a stubbed CC environment.

Task checks require Ruby and Rake; signal and timeout checks require Docker.
CAPI_TEST_IMAGE may select the locally built Cloud Controller image.
"""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
import uuid


SCRIPT = Path(__file__).resolve().parents[1] / "helm/files/cc-worker-cleanup.rb"
IMAGE = os.environ.get("CAPI_TEST_IMAGE", "ruby:4.0.9-slim")
WORKER_NAME = "cc_global_worker.cc-worker.2.1"
FAKE_RAKEFILE = """
require 'json'
task :environment do
  puts 'Loaded environment'
end
namespace :jobs do
  task :clear_pending_locks, [:name] => :environment do |_task, args|
    puts JSON.generate(owner: args.name)
    if ENV.fetch('FAIL_OWNER', '').empty? || ENV['FAIL_OWNER'] == args.name
      raise 'database unavailable' if ENV['RESULT'] == 'failure'
      sleep 60 if ENV['RESULT'] == 'stuck'
    end
    puts JSON.generate(cleared: args.name)
  end
end
"""


def cleaned_owners(logs):
    return [json.loads(line)["owner"] for line in logs.splitlines() if line.startswith('{"owner":')]


class WorkerCleanupTasksTest(unittest.TestCase):
    def run_cleanup(self, threads, **environment):
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "Rakefile").write_text(FAKE_RAKEFILE)
            return subprocess.run(
                ["ruby", str(SCRIPT), "--cleanup"], cwd=directory,
                env={**os.environ, "WORKER_NAME": WORKER_NAME, "WORKER_THREADS": str(threads),
                     "RESULT": "success", "FAIL_OWNER": "", **environment},
                capture_output=True, text=True, timeout=10,
            )

    def test_task_runs_for_each_owner_with_one_environment_boot(self):
        for threads in [0, 3]:
            with self.subTest(threads=threads):
                result = self.run_cleanup(threads)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(cleaned_owners(result.stdout), [WORKER_NAME] + [
                    f"{WORKER_NAME} thread:{index}" for index in range(1, threads + 1)
                ])
                self.assertEqual(result.stdout.count("Loaded environment"), 1)

    def test_task_failures_do_not_prevent_remaining_cleanup(self):
        owners = [WORKER_NAME] + [f"{WORKER_NAME} thread:{index}" for index in range(1, 4)]
        for fail_owner in [WORKER_NAME, owners[2], owners[3], ""]:
            with self.subTest(fail_owner=fail_owner):
                result = self.run_cleanup(3, RESULT="failure", FAIL_OWNER=fail_owner)
                failed = [fail_owner] if fail_owner else owners
                successful = [owner for owner in owners if owner not in failed]
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(cleaned_owners(result.stdout), owners)
                self.assertEqual([
                    json.loads(line)["cleared"] for line in result.stdout.splitlines()
                    if line.startswith('{"cleared":')
                ], successful)
                self.assertEqual(result.stdout.count("Loaded environment"), 1)
                for owner in failed:
                    self.assertIn(
                        f"Worker lock cleanup failed for {owner}: RuntimeError: database unavailable",
                        result.stderr,
                    )
                self.assertIn(
                    f"Worker lock cleanup incomplete: {len(successful)} succeeded, {len(failed)} failed",
                    result.stderr,
                )
                self.assertNotIn("Cleared pending locks", result.stdout)


class WorkerCleanupTest(unittest.TestCase):
    def docker(self, *arguments, timeout=15):
        return subprocess.run(
            ["docker", *arguments], check=True, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout,
        ).stdout.strip()

    def exercise(self, threads, result="success"):
        name = "capi-cleanup-test-" + uuid.uuid4().hex[:12]
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory)
            fixture.chmod(0o755)
            (fixture / "Rakefile").write_text(FAKE_RAKEFILE)
            # Stub only the CC tasks; Ruby, Rake, exec, timeout and signals are real.
            bundle = fixture / "bundle"
            bundle.write_text('#!/bin/sh\n[ "$1" = exec ] || exit 99\nshift\nexec "$@"\n')
            bundle.chmod(0o755)
            try:
                self.docker(
                    "run", "-d", "--name", name, "--network", "none", "--user", "1000:1000",
                    "--mount", f"type=bind,src={SCRIPT},dst=/cleanup.rb,readonly",
                    "--mount", f"type=bind,src={fixture},dst=/test,readonly",
                    "--workdir", "/test", "-e", "PATH=/test:/usr/local/bin:/usr/bin:/bin",
                    "-e", f"WORKER_NAME={WORKER_NAME}",
                    "-e", f"WORKER_THREADS={threads}", "-e", f"RESULT={result}",
                    "-e", "CLEANUP_TIMEOUT_SECONDS=2", IMAGE, "ruby", "/cleanup.rb",
                    timeout=120,
                )
                deadline = time.monotonic() + 10
                while "Waiting for worker shutdown" not in self.docker("logs", name):
                    self.assertLess(time.monotonic(), deadline, "sidecar did not start")
                    time.sleep(0.1)
                time.sleep(0.2)
                self.assertNotIn("Clearing pending locks", self.docker("logs", name))
                start = time.monotonic()
                self.docker("kill", "--signal=TERM", name)
                status = int(self.docker("wait", name, timeout=10))
                elapsed = time.monotonic() - start
                logs = self.docker("logs", name)
                self.assertEqual(cleaned_owners(logs), [WORKER_NAME] + [
                    f"{WORKER_NAME} thread:{index}" for index in range(1, threads + 1)
                ])
                return status, elapsed, logs
            finally:
                subprocess.run(["docker", "rm", "-f", name], capture_output=True, timeout=15)

    def test_single_worker_cleanup_waits_for_term(self):
        status, _, logs = self.exercise(0)
        self.assertEqual(status, 0, logs)
        self.assertIn("Cleared pending locks", logs)

    def test_threaded_worker_configuration_reaches_cleanup(self):
        status, _, logs = self.exercise(3)
        self.assertEqual(status, 0, logs)

    def test_cleanup_failure_is_reported(self):
        status, _, logs = self.exercise(3, "failure")
        self.assertEqual(status, 1, logs)
        self.assertIn(f"Worker lock cleanup failed for {WORKER_NAME}: RuntimeError: database unavailable", logs)
        self.assertIn("Worker lock cleanup incomplete: 0 succeeded, 4 failed", logs)
        self.assertNotIn("Cleared pending locks", logs)

    def test_cleanup_timeout_is_bounded(self):
        status, elapsed, logs = self.exercise(0, "stuck")
        self.assertEqual(status, 137, logs)
        self.assertLess(elapsed, 6, logs)
        self.assertIn("sending signal KILL", logs)


if __name__ == "__main__":
    unittest.main()
