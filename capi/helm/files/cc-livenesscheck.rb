require 'json'
require 'socket'
require 'timeout'

class CcLivenesscheck
  def initialize(socket_path: '/var/run/cloud_controller_metrics.sock', state_path: '/tmp/cc-healthcheck-state.json')
    @socket_path = socket_path
    @state_path = state_path
  end

  def healthy?
    # emptyDir survives container restarts. PID 1's kernel start time identifies
    # this container run even when CC is wrapped by the timeout command.
    container_start = File.read('/proc/1/stat').split(') ', 2).last.split.fetch(19)
    state = File.exist?(@state_path) ? JSON.parse(File.read(@state_path)) : {}
    if state['container_start'] != container_start
      state = { 'container_start' => container_start, 'last_ok' => monotonic_time }
      save_state(state)
    end

    code = status_code
    # Like curl exit code 7 in BOSH, an unavailable listener is not a restart
    # signal. Do not update last_ok; a later non-200 still checks the deadline.
    return true if code == :unavailable

    now = monotonic_time
    if code == '200'
      state['last_ok'] = now
      save_state(state)
      return true
    end

    if code == '503'
      warn 'CC status endpoint returned 503 (unhealthy)'
      return false
    end

    elapsed = now - state.fetch('last_ok')
    warn "CC status endpoint returned #{code || 'no HTTP status'}; no 200 for #{elapsed.round} seconds"
    elapsed < 600
  end

  private

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def save_state(state)
    # A probe killed by kubelet must not leave a partially written state file.
    File.write("#{@state_path}.tmp", JSON.generate(state))
    File.rename("#{@state_path}.tmp", @state_path)
  end

  def status_code
    Timeout.timeout(2) do
      UNIXSocket.open(@socket_path) do |socket|
        socket.write("GET /internal/v4/status HTTP/1.0\r\nUser-Agent: cc-livenesscheck\r\n\r\n")
        socket.gets&.split&.at(1)
      end
    end
  rescue Errno::ENOENT, Errno::ECONNREFUSED => error
    warn "CC status listener unavailable: #{error.message}"
    :unavailable
  rescue Timeout::Error, IOError, SystemCallError => error
    warn "CC status request failed: #{error.class}: #{error.message}"
    nil
  end
end

exit(CcLivenesscheck.new.healthy? ? 0 : 1) if $PROGRAM_NAME == __FILE__
