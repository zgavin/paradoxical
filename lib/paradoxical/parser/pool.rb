require "etc"

# A bounded pool of Ractors that run `Paradoxical::Parser.parse` in
# parallel. Each worker Ractor waits on its incoming port for a
# `[job_id, bytes]` pair, runs the pure-Rust parse (Ractor-safe via
# the `rb_ext_ractor_safe` flag in lib.rs), and writes the result to
# a shared outbound port. A collector thread on the main Ractor reads
# from the port and resolves the corresponding `Paradoxical::Future`.
#
# NB: This implementation is preserved on the `experiment/ractor-pool`
# branch as a reference; it does NOT outperform the simpler
# `nogvl + Thread pool` approach on master. For our typical file
# workload (~3 ms per parse on imperator), the per-parse inter-Ractor
# message-passing overhead dominates the parallelism win, and the
# pool actually runs SLOWER than a serial parse in the smoke
# benchmark (~250 vs 318 files/s on imperator). Keeping the design
# here for posterity / possible future re-evaluation if Ruby's Ractor
# implementation matures or our parse cost grows enough to amortize
# the message overhead.
class Paradoxical::Parser::Pool
  def initialize n_workers: nil
    @n_workers = n_workers || Etc.nprocessors
    @next_job_id = 0
    @next_worker = 0
    @jobs = {}     # job_id => [future, post_process_proc]
    @mutex = Mutex.new

    # Single shared outbound port; every worker writes its result here,
    # the collector thread on this Ractor reads them off in order.
    @results_port = Ractor::Port.new

    @workers = @n_workers.times.map do
      Ractor.new(@results_port) do |results_port|
        loop do
          msg = Ractor.receive
          break if msg.nil?

          job_id, bytes = msg
          result =
            begin
              [job_id, :ok, Paradoxical::Parser.parse(bytes)]
            rescue Paradoxical::Parser::ParseError => e
              [job_id, :parse_error, e.message]
            rescue StandardError => e
              [job_id, :error, e.class.name, e.message]
            end
          results_port.send(result)
        end
      end
    end

    @collector = Thread.new { collector_loop }
    @collector.report_on_exception = true
  end

  # Submit a parse job. Returns a `Paradoxical::Future` that resolves
  # with the result of `post_process.call(parsed_document)`, or with
  # the bare Document if no block is given.
  #
  # `post_process` runs on the collector thread (not in the Ractor)
  # so it can safely close over caller state — Game, Mod, file path,
  # etc. — and mutate caches without crossing the Ractor boundary.
  def submit bytes, &post_process
    future = Paradoxical::Future.new
    job_id = nil

    @mutex.synchronize do
      job_id = @next_job_id
      @next_job_id += 1
      @jobs[job_id] = [future, post_process]
    end

    # Round-robin worker selection. Simple; not work-stealing, but
    # adequate when workloads per file are roughly uniform (which
    # they are for our smoke).
    worker = nil
    @mutex.synchronize do
      worker = @workers[@next_worker]
      @next_worker = (@next_worker + 1) % @n_workers
    end
    worker.send([job_id, bytes])

    future
  end

  def shutdown
    @workers.each do |w| w.send(nil) end
    @collector.kill if @collector.alive?
  end

  private

  def collector_loop
    loop do
      msg = @results_port.receive
      next if msg.nil?

      job_id = msg[0]
      future, post_process = nil, nil
      @mutex.synchronize do
        future, post_process = @jobs.delete(job_id)
      end
      next if future.nil?

      case msg[1]
      when :ok
        document = msg[2]
        begin
          result = post_process ? post_process.call(document) : document
          future.fulfill(result)
        rescue StandardError => e
          future.reject(e)
        end
      when :parse_error
        future.reject(Paradoxical::Parser::ParseError.new(msg[2]))
      when :error
        klass = Object.const_get(msg[2]) rescue StandardError
        future.reject(klass.new(msg[3]))
      end
    end
  rescue Ractor::ClosedError
    # Pool shut down; exit gracefully.
  end
end
