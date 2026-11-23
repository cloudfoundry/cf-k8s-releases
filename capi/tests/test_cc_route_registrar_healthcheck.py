"""Exercise the chart-rendered CC route check with real TLS, curl and timeout.

Requires Helm, Mike Farah's yq v4, Docker and the built production image selected
with ROUTE_REGISTRAR_TEST_IMAGE (default route-registrar:latest). ruby:4.0.9-slim
provides only the TLS fixture. The production container shares its localhost and
mounts the rendered script read-only, emulating the CAPI chart's ConfigMap.
"""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

import test_api_lifecycle


IMAGE = os.environ.get("ROUTE_REGISTRAR_TEST_IMAGE", "route-registrar:latest")
SCRIPT = "/etc/route-registrar-template/check-cc-health.sh"
TLS_FIXTURE = """
require 'json'
require 'socket'
require 'openssl'
key = OpenSSL::PKey::RSA.new(2048)
certificate = OpenSSL::X509::Certificate.new
certificate.version = 2
certificate.serial = 1
certificate.subject = certificate.issuer = OpenSSL::X509::Name.parse('/CN=localhost')
certificate.public_key = key.public_key
certificate.not_before = Time.now - 60
certificate.not_after = Time.now + 3600
certificate.sign(key, OpenSSL::Digest::SHA256.new)
context = OpenSSL::SSL::SSLContext.new
context.key = key
context.cert = certificate
mutex = Mutex.new
listeners = [9024, 9443].map do |port|
  server = OpenSSL::SSL::SSLServer.new(TCPServer.new('127.0.0.1', port), context)
  Thread.new do
    loop do
      connection = server.accept
      Thread.new(connection) do |client|
        begin
          request = client.gets.strip
          while (line = client.gets)
            break if line == "\\r\\n"
          end
          code = mutex.synchronize do
            state = JSON.parse(File.read('/test/state.json'))
            state.fetch('requests') << { request: request, port: port }
            responses = state.fetch('responses')
            response = responses.length > 1 ? responses.shift : responses.first
            File.write('/test/state.json', JSON.generate(state))
            response
          end
          if code == 'hang'
            sleep 60
          else
            client.write("HTTP/1.1 #{code} Status\\r\\nContent-Length: 0\\r\\nConnection: close\\r\\n\\r\\n")
          end
        ensure
          client.close
        end
      end
    end
  end
end
File.write('/test/ready', 'ready')
listeners.each(&:join)
"""
TIMED_PROBE = f"""
start=$(date +%s%N)
{SCRIPT}
status=$?
finish=$(date +%s%N)
printf '\\nCHECK_ELAPSED_NS=%s\\n' "$((finish - start))" >&2
exit "$status"
"""


class CcRouteRegistrarHealthcheckTest(unittest.TestCase):
    @staticmethod
    def docker(*arguments, timeout=15):
        return subprocess.run(
            ["docker", *arguments], check=True, capture_output=True,
            text=True, timeout=timeout,
        ).stdout.strip()

    @staticmethod
    def remove_container(container):
        subprocess.run(
            ["docker", "rm", "-f", container], capture_output=True, timeout=15,
        )

    @classmethod
    def setUpClass(cls):
        renderer = test_api_lifecycle.ApiLifecycleTest()
        cls.scripts = {}
        for port in [9024, 9443, 9444]:
            documents = renderer.render(f"cloudController.config.publicTLS.port={port}")
            config = renderer.resource(
                documents, "ConfigMap", "cloud-controller-route-registrar-config",
            )
            cls.scripts[port] = config["data"]["check-cc-health.sh"]
        directory = tempfile.TemporaryDirectory()
        cls.addClassCleanup(directory.cleanup)
        cls.fixture = Path(directory.name)
        cls.script_path = cls.fixture / "check-cc-health.sh"
        cls.install_script(9024)
        cls.state_path = cls.fixture / "state.json"
        cls.state_path.write_text(json.dumps({"responses": [200], "requests": []}))
        fixture_container = cls.docker(
            "run", "-d", "--network", "none",
            "--mount", f"type=bind,src={cls.fixture},dst=/test",
            "ruby:4.0.9-slim", "ruby", "-e", TLS_FIXTURE, timeout=120,
        )
        cls.addClassCleanup(cls.remove_container, fixture_container)
        deadline = time.monotonic() + 10
        while not (cls.fixture / "ready").exists():
            if time.monotonic() >= deadline:
                raise AssertionError(
                    "TLS fixture did not start: " + cls.docker("logs", fixture_container)
                )
            time.sleep(0.05)
        cls.container = cls.docker(
            "run", "-d", "--network", f"container:{fixture_container}",
            "--mount", f"type=bind,src={cls.fixture},dst=/etc/route-registrar-template,readonly",
            "--entrypoint", "sleep", IMAGE, "infinity", timeout=120,
        )
        cls.addClassCleanup(cls.remove_container, cls.container)

    @classmethod
    def install_script(cls, port):
        # Replace rather than overwrite the existing read-only ConfigMap script.
        with tempfile.NamedTemporaryFile("w", dir=cls.fixture, delete=False) as script:
            script.write(cls.scripts[port])
        replacement = Path(script.name)
        replacement.chmod(0o555)
        replacement.rename(cls.script_path)

    def configure(self, *responses):
        self.state_path.write_text(json.dumps({"responses": responses, "requests": []}))

    def requests(self):
        return json.loads(self.state_path.read_text())["requests"]

    def probe(self, port=9024, timed=False):
        self.install_script(port)
        command = ["docker", "exec", self.container]
        command.extend(["sh", "-c", TIMED_PROBE] if timed else [SCRIPT])
        return subprocess.run(command, capture_output=True, text=True, timeout=15)

    def test_rendered_healthcheck_is_executable_and_curl_is_available(self):
        self.install_script(9024)
        self.docker("exec", self.container, "test", "-x", SCRIPT)
        self.assertEqual(self.docker("exec", self.container, "cat", SCRIPT), self.scripts[9024].strip())
        self.assertIn("curl", self.docker("exec", self.container, "curl", "--version"))

    def test_healthy_response_on_default_tls_port_succeeds(self):
        self.configure(200)
        result = self.probe()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.requests(), [{"request": "GET /healthz HTTP/1.1", "port": 9024}])

    def test_http_503_fails_after_retries(self):
        self.configure(503)
        result = self.probe()
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn("503", result.stderr)
        self.assertGreaterEqual(len(self.requests()), 2)

    def test_connection_refused_fails(self):
        self.configure(200)
        result = self.probe(port=9444)
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(self.requests(), [])

    def test_hanging_endpoint_finishes_before_registrars_six_second_timeout(self):
        self.configure("hang")
        result = self.probe(timed=True)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertGreaterEqual(len(self.requests()), 1)
        # Measure in the production container, excluding Docker CLI/exec overhead.
        elapsed_line = next(
            line for line in result.stderr.splitlines() if line.startswith("CHECK_ELAPSED_NS=")
        )
        elapsed = int(elapsed_line.split("=", 1)[1]) / 1_000_000_000
        self.assertGreaterEqual(elapsed, 2, result.stderr)
        self.assertLess(elapsed, 6, result.stderr)

    def test_transient_503_retries_until_healthy(self):
        self.configure(503, 200)
        result = self.probe()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.requests(), [
            {"request": "GET /healthz HTTP/1.1", "port": 9024},
            {"request": "GET /healthz HTTP/1.1", "port": 9024},
        ])

    def test_custom_tls_port_is_used(self):
        self.configure(200)
        result = self.probe(port=9443)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.requests(), [{"request": "GET /healthz HTTP/1.1", "port": 9443}])


if __name__ == "__main__":
    unittest.main()
