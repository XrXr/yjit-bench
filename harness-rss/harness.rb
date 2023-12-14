require 'benchmark'
require_relative "../harness/harness-common"

# Minimum number of benchmarking iterations
MAX_BENCH_ITRS = Integer(ENV.fetch('MAX_BENCH_ITRS', 1000))

# Minimum benchmarking time in seconds
MAX_BENCH_SECONDS = Integer(ENV.fetch('MAX_BENCH_SECONDS', 60 * 60))

puts RUBY_DESCRIPTION

# Takes a block as input
def run_benchmark(_num_itrs_hint)
  times = []
  total_time = 0
  num_itrs = 0

  begin
    time = Benchmark.realtime { yield }
    num_itrs += 1
    rss = get_rss
    if stats = RubyVM::YJIT.runtime_stats
      alloc = stats[:yjit_alloc_size] / 1024.0 / 1024.0
      code_size = stats[:code_region_size] / 1024.0 / 1024.0
    else
      alloc = 0
      code_size = 0
    end
    pages = GC.stat(:heap_allocated_pages)
    objs = GC.stat(:heap_live_slots)

    time_ms = (1000 * time).to_i
    puts sprintf("itr \#%d: %dms RSS: %dMiB YJIT-code=%dMiB YJIT-meta=%dMiB heap_allocated_pages=%d heap_live_slots=%d", num_itrs, time_ms, (rss / 1024.0 / 1024.0), code_size, alloc, pages, objs)

    GC.compact

    times << time
    total_time += time
  end until num_itrs >= MAX_BENCH_ITRS || total_time >= MAX_BENCH_SECONDS

  return_results([], times)
end
