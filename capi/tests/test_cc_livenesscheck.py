"""Exercise CC probes across separate Ruby invocations with real Unix listeners.

Only time and the Linux container identity are stubbed in the policy tests.
The container test uses the production entry point and kernel identity.
Requires Ruby and Docker; CAPI_TEST_IMAGE may select the CC image.
"""

import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "helm/files/cc-livenesscheck.rb"
STARTUP_SCRIPT = Path(__file__).resolve().parents[1] / "helm/files/cc-startupcheck.rb"
DRIVER = """
require ARGV.shift
module Process
  def self.clock_gettime(_clock)
    Float(ENV.fetch('TEST_NOW'))
  end
end
class File
  class << self
    alias_method :original_read, :read
    def read(path)
      return "1 (timeout wrapper) " + (['S'] * 19 + [ENV.fetch('TEST_CONTAINER')]).join(' ') if path == '/proc/1/stat'
      original_read(path)
    end
  end
end
exit(CcLivenesscheck.new(socket_path: ARGV[0], state_path: ARGV[1]).healthy? ? 0 : 1)
"""
CONTAINER_DRIVER = """
require 'json'
require 'socket'
server = UNIXServer.new('/var/run/cloud_controller_metrics.sock')
code = 200
listener = Thread.new do
  loop do
    connection = server.accept
    while (line = connection.gets)
      break if line == "\\r\\n"
    end
    connection.write("HTTP/1.0 #{code} Status\\r\\n\\r\\n")
    connection.close
  end
end
def probe(expected)
  system('ruby', '/livenesscheck.rb')
  raise "Unexpected probe exit status: #{$?.exitstatus}, expected #{expected}" unless $?.exitstatus == expected
end
state_path = '/tmp/cc-healthcheck-state.json'
probe(0)
state = JSON.parse(File.read(state_path))
raise 'Invalid container identity' unless state.fetch('container_start') == File.read('/proc/1/stat').split(') ', 2).last.split.fetch(19)
code = 429
probe(0)
state['last_ok'] -= 600
File.write(state_path, JSON.generate(state))
probe(1)
state['container_start'] = 'previous-container'
File.write(state_path, JSON.generate(state))
probe(0)
code = 503
probe(1)
code = 200
probe(0)
listener.kill
server.close
"""
STARTUP_DRIVER = """
require 'socket'
path = '/var/run/cloud_controller.sock'
server = UNIXServer.new(path)
listener = Thread.new do
  [200, 429, 503, nil].each do |code|
    connection = server.accept
    request = ''
    while (line = connection.gets)
      request << line
      break if line == "\\r\\n"
    end
    raise "Unexpected request: #{request.inspect}" unless request == "GET /healthz HTTP/1.0\\r\\n\\r\\n"
    connection.write("HTTP/1.0 #{code} Status\\r\\n\\r\\n") if code
    connection.close
  end
end
[0, 1, 1, 1].each do |expected|
  system('ruby', '/startupcheck.rb')
  raise "Unexpected probe exit status: #{$?.exitstatus}, expected #{expected}" unless $?.exitstatus == expected
end
listener.value
server.close
File.unlink(path)
system('ruby', '/startupcheck.rb')
raise 'Missing socket must fail startup' if $?.success?
"""


class CcLivenesscheckTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.socket_path = str(Path(self.directory.name) / "status.sock")
        self.state_path = Path(self.directory.name) / "state.json"

    def probe(self, code, now, container="first", delay=False):
        requests = []
        errors = []
        listener = socket.socket(socket.AF_UNIX)
        listener.bind(self.socket_path)
        listener.listen(1)
        listener.settimeout(5)
        done = threading.Event()

        def serve():
            try:
                with listener.accept()[0] as connection:
                    connection.settimeout(5)
                    request = b""
                    while b"\r\n\r\n" not in request:
                        data = connection.recv(1024)
                        if not data:
                            break
                        request += data
                    requests.append(request.decode())
                    if delay:
                        done.wait(5)
                    elif code is not None:
                        connection.sendall(f"HTTP/1.0 {code} Status\r\n\r\n".encode())
            except Exception as error:
                errors.append(error)

        server = threading.Thread(target=serve)
        server.start()
        try:
            result = self.run_probe(now, container)
        finally:
            done.set()
            server.join(timeout=6)
            listener.close()
            os.unlink(self.socket_path)
        self.assertFalse(server.is_alive())
        self.assertEqual(errors, [])
        self.assertEqual(requests, [
            "GET /internal/v4/status HTTP/1.0\r\nUser-Agent: cc-livenesscheck\r\n\r\n"
        ])
        return result

    def run_probe(self, now, container="first"):
        return subprocess.run(
            ["ruby", "-e", DRIVER, str(SCRIPT), self.socket_path, str(self.state_path)],
            env={**os.environ, "TEST_NOW": str(now), "TEST_CONTAINER": container},
            capture_output=True, text=True, timeout=5,
        )

    def test_busy_deadline_and_healthy_response_resets_timer(self):
        self.assertEqual(self.probe(429, 100).returncode, 0)
        self.assertEqual(self.probe(429, 699).returncode, 0)
        result = self.probe(429, 700)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("no 200 for 600 seconds", result.stderr)
        self.assertEqual(self.probe(200, 710).returncode, 0)
        self.assertEqual(self.probe(429, 1309).returncode, 0)
        self.assertEqual(self.probe(429, 1310).returncode, 1)

    def test_unhealthy_response_fails_immediately(self):
        result = self.probe(503, 100)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("503 (unhealthy)", result.stderr)

    def test_unexpected_or_missing_http_status_uses_same_deadline(self):
        for code in [500, 404, 302, None]:
            with self.subTest(code=code):
                self.assertEqual(self.probe(200, 100).returncode, 0)
                self.assertEqual(self.probe(code, 699).returncode, 0)
                self.assertEqual(self.probe(code, 700).returncode, 1)

    def test_request_timeout_is_bounded_and_uses_same_deadline(self):
        self.assertEqual(self.probe(200, 100).returncode, 0)
        result = self.probe(None, 699, delay=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Timeout::Error", result.stderr)
        self.assertEqual(self.probe(None, 700, delay=True).returncode, 1)

    def test_missing_or_refused_listener_does_not_reset_timer(self):
        self.assertEqual(self.probe(200, 100).returncode, 0)
        self.assertEqual(self.run_probe(800).returncode, 0)
        listener = socket.socket(socket.AF_UNIX)
        listener.bind(self.socket_path)
        listener.close()
        result = self.run_probe(810)
        self.assertEqual(result.returncode, 0, result.stderr)
        os.unlink(self.socket_path)
        self.assertEqual(json.loads(self.state_path.read_text())["last_ok"], 100)
        self.assertEqual(self.probe(429, 820).returncode, 1)

    def test_container_restart_resets_stale_shared_state(self):
        self.assertEqual(self.probe(429, 100).returncode, 0)
        self.assertEqual(self.probe(429, 700).returncode, 1)
        self.assertEqual(self.probe(429, 710, container="second").returncode, 0)
        self.assertEqual(self.probe(429, 1309, container="second").returncode, 0)
        self.assertEqual(self.probe(429, 1310, container="second").returncode, 1)


class CcLivenesscheckContainerTest(unittest.TestCase):
    def test_startup_check_requires_a_healthy_api_response(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory).chmod(0o777)
            result = subprocess.run([
                "docker", "run", "--rm", "--network", "none", "--user", "1000:1000",
                "--mount", f"type=bind,src={STARTUP_SCRIPT},dst=/startupcheck.rb,readonly",
                "--mount", f"type=bind,src={directory},dst=/var/run",
                os.environ.get("CAPI_TEST_IMAGE", "ruby:4.0.9-slim"),
                "ruby", "-e", STARTUP_DRIVER,
            ], capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_production_entry_point_and_linux_container_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory).chmod(0o777)
            result = subprocess.run([
                "docker", "run", "--rm", "--network", "none", "--user", "1000:1000",
                "--mount", f"type=bind,src={SCRIPT},dst=/livenesscheck.rb,readonly",
                "--mount", f"type=bind,src={directory},dst=/var/run",
                os.environ.get("CAPI_TEST_IMAGE", "ruby:4.0.9-slim"),
                "ruby", "-e", CONTAINER_DRIVER,
            ], capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
