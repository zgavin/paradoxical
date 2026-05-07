# A minimal future/promise. Created in the unfulfilled state; resolved
# exactly once with `fulfill(value)` or `reject(error)`. Callers block
# on `.value` (alias `.join`) until resolution.
#
# We roll our own rather than pulling `concurrent-ruby` because we
# need exactly two operations (resolve and await) and the dep would
# add ~200KB for ~30 lines of behavior.
#
# Used by `Paradoxical::Parser::Pool` so `parse_file` can return a
# Future the caller chooses to await individually (sync) or in batch
# (parallel).
class Paradoxical::Future
  def initialize
    @mutex = Mutex.new
    @cond = ConditionVariable.new
    @resolved = false
    @value = nil
    @error = nil
  end

  def fulfill value
    @mutex.synchronize do
      raise "Future already resolved" if @resolved

      @value = value
      @resolved = true
      @cond.broadcast
    end
  end

  def reject error
    @mutex.synchronize do
      raise "Future already resolved" if @resolved

      @error = error
      @resolved = true
      @cond.broadcast
    end
  end

  # Block until the future is resolved, then return the value (or
  # re-raise the error). Multiple callers may await the same future;
  # all wake up on resolution.
  def value
    @mutex.synchronize do
      @cond.wait(@mutex) until @resolved
    end
    raise @error if @error

    @value
  end

  alias join value

  def resolved?
    @mutex.synchronize { @resolved }
  end
end
