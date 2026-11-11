# Native sidecar: only start cleanup when kubelet signals us after worker exit.
$stdout.sync = true

if ARGV.delete('--cleanup')
  begin
    require 'rake'
    Rake.application.init
    Rake.application.load_rakefile
    Rake::Task['environment'].invoke
    RakeConfig.context = :worker

    worker_name = ENV.fetch('WORKER_NAME')
    puts "Clearing pending locks for #{worker_name}"
    # The upstream rake task accepts only a name. Passing num_threads here also
    # clears each exact thread owner through the upstream clear_locks! method.
    CloudController::DelayedWorker.new(
      queues: [],
      name: worker_name,
      num_threads: Integer(ENV.fetch('WORKER_THREADS', '0'))
    ).clear_locks!
    puts "Cleared pending locks for #{worker_name}"
    exit 0
  rescue StandardError => error
    warn "Worker lock cleanup failed: #{error.class}: #{error.message}"
    exit 1
  end
end

stopping = false
Signal.trap('TERM') { stopping = true }
puts 'Waiting for worker shutdown before clearing locks'
sleep 1 until stopping

# Bound both application boot and database cleanup. A stuck cleanup must not
# outlive the Pod deadline; timeout logs a diagnostic and exits nonzero on KILL.
exec 'timeout', '--foreground', '--verbose', '--signal=KILL',
     "#{ENV.fetch('CLEANUP_TIMEOUT_SECONDS')}s",
     'bundle', 'exec', 'ruby', __FILE__, '--cleanup'
