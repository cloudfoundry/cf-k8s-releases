# Native sidecar: only start cleanup when kubelet signals us after worker exit.
$stdout.sync = true

if ARGV.delete('--cleanup')
  begin
    require 'rake'
    Rake.application.init
    Rake.application.load_rakefile
    worker_name = ENV.fetch('WORKER_NAME')
    worker_names = [worker_name] + (1..Integer(ENV.fetch('WORKER_THREADS', '0'))).map do |index|
      "#{worker_name} thread:#{index}"
    end
    puts "Clearing pending locks for #{worker_name}"
    Rake::Task[:environment].invoke
    RakeConfig.context = :worker
    # The upstream rake task initializes BackgroundJobEnvironment on every call.
    # Initialize once without a readiness listener for this cleanup-only process.
    BackgroundJobEnvironment.new(RakeConfig.config).setup_environment
    failed_names = []
    worker_names.each do |name|
      begin
        # Use the same owner-scoped operation as jobs:clear_pending_locks.
        Delayed::Job.clear_locks!(name)
      rescue StandardError => error
        warn "Worker lock cleanup failed for #{name}: #{error.class}: #{error.message}"
        failed_names << name
      end
    end
    unless failed_names.empty?
      warn "Worker lock cleanup incomplete: #{worker_names.length - failed_names.length} succeeded, #{failed_names.length} failed"
      exit 1
    end
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
