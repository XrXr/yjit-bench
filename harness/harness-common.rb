# Ensure the ruby in PATH is the ruby running this, so we can safely shell out to other commands
ruby_in_path = `ruby -e 'print RbConfig.ruby'`
unless ruby_in_path == RbConfig.ruby
  abort "The ruby running this script (#{RbConfig.ruby}) is not the first ruby in PATH (#{ruby_in_path})"
end

# Seed the global random number generator for repeatability between runs
Random.srand(1337)

# It's totally fine to include commands like "bundle" or "ruby". In those cases, the path should handle
# running the correct version.
def run_cmd(*args, silent: true)
  puts "Command: #{args.join(" ")}" unless silent
  system(*args) || raise("Error running cmd #{args.inspect}: #{$!.inspect}")
end

def setup_cmds(c)
  c.each do |cmd|
    success = run_cmd(cmd)
    raise "Couldn't run setup command for benchmark in #{Dir.pwd.inspect}!" unless success
  end
end

# Set up a Gemfile, install gems and do extra setup
def use_gemfile(extra_setup_cmd: nil)
  # Benchmarks should normally set their current directory and then call this method.

  setup_cmds(["bundle check 2> /dev/null || bundle install", extra_setup_cmd].compact)

  # Need to be in the appropriate directory for this...
  require "bundler/setup"
end

# This returns its best estimate of the Resident Set Size in bytes.
# That's roughly the amount of memory the process takes, including shareable resources.
# RSS reference: https://stackoverflow.com/questions/7880784/what-is-rss-and-vsz-in-linux-memory-management
def get_rss
  mem_rollup_file = "/proc/#{Process.pid}/smaps_rollup"
  if File.exist?(mem_rollup_file)
    # First, grab a line like "62796 kB". Checking the Linux kernel source, Rss will always be in kB.
    rss_desc = File.read(mem_rollup_file).lines.detect { |line| line.start_with?("Rss") }.split(":", 2)[1].strip
    1024 * rss_desc.to_i
  else
    # Collect our own peak mem usage as soon as reasonable after finishing the last iteration.
    # This method is only accurate to kilobytes, but is nicely portable and doesn't require
    # any extra gems/dependencies.
    mem = `ps -o rss= -p #{Process.pid}`
    1024 * mem.to_i
  end
end

YJIT_BENCH_RESULTS = {
  "RUBY_DESCRIPTION" => RUBY_DESCRIPTION,
}
# Grab this initially, not at exit, before the benchmark can do a chdir
default_path = "data/results-#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}-#{Time.now.strftime('%F-%H%M%S')}.json"
yb_env_var = ENV.fetch("RESULT_JSON_PATH", default_path)
YB_OUTPUT_FILE = File.expand_path yb_env_var

def return_results(name, values)
  YJIT_BENCH_RESULTS[name] = values
end

at_exit do
  require "json"
  out_path = YB_OUTPUT_FILE
  system('mkdir', '-p', File.dirname(out_path))

  # Using default path? Print where we put it.
  puts "Writing file #{out_path}" unless ENV["RESULT_JSON_PATH"]

  File.write(out_path, JSON.pretty_generate(YJIT_BENCH_RESULTS))
end
