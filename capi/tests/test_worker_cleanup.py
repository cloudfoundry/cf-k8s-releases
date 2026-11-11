"""Exercise the sidecar's signals and deadlines with a stubbed CC environment.

Requires Docker. CAPI_TEST_IMAGE may select the locally built Cloud Controller image.
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
FAKE_RAKE = """
require 'json'
module Rake
  def self.application; self; end
  def self.init; raise 'unexpected arguments' unless ARGV.empty?; end
  def self.load_rakefile; end
  class Task
    def self.[](name)
      raise 'wrong task' unless name == 'environment'
      new
    end
    def invoke; end
  end
end
class RakeConfig
  class << self
    attr_accessor :context
  end
end
module CloudController
  class DelayedWorker
    def initialize(**options); @options = options; end
    def clear_locks!
      raise 'wrong context' unless RakeConfig.context == :worker
      puts JSON.generate(@options)
      case ENV.fetch('RESULT', 'success')
      when 'failure' then raise 'database unavailable'
      when 'stuck' then sleep 60
      end
    end
  end
end
"""


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
            (fixture / "rake.rb").write_text(FAKE_RAKE)
            # Stub only application boot; Ruby, exec, timeout and signals are real.
            bundle = fixture / "bundle"
            bundle.write_text('#!/bin/sh\n[ "$1" = exec ] || exit 99\nshift\nexec "$@"\n')
            bundle.chmod(0o755)
            try:
                self.docker(
                    "run", "-d", "--name", name, "--network", "none", "--user", "1000:1000",
                    "--mount", f"type=bind,src={SCRIPT},dst=/cleanup.rb,readonly",
                    "--mount", f"type=bind,src={fixture},dst=/test,readonly",
                    "-e", "RUBYLIB=/test", "-e", "PATH=/test:/usr/local/bin:/usr/bin:/bin",
                    "-e", "WORKER_NAME=cc_global_worker.cc-worker.2.1",
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
                options = next(json.loads(line) for line in logs.splitlines() if line.startswith('{"queues":'))
                self.assertEqual(options, {
                    "queues": [], "name": "cc_global_worker.cc-worker.2.1", "num_threads": threads,
                })
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
        status, _, logs = self.exercise(0, "failure")
        self.assertEqual(status, 1, logs)
        self.assertIn("Worker lock cleanup failed: RuntimeError: database unavailable", logs)
        self.assertNotIn("Cleared pending locks", logs)

    def test_cleanup_timeout_is_bounded(self):
        status, elapsed, logs = self.exercise(0, "stuck")
        self.assertEqual(status, 137, logs)
        self.assertLess(elapsed, 6, logs)
        self.assertIn("sending signal KILL", logs)


if __name__ == "__main__":
    unittest.main()
