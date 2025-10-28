# lib/single_flight.rb
require "concurrent/map"

class SingleFlight
  def initialize
    @locks = Concurrent::Map.new
  end

  # serialize concurrent work by key
  def do(key)
    lock = @locks.compute_if_absent(key) { Mutex.new }
    lock.synchronize { yield }
  ensure
    # best-effort cleanup; only delete if same lock is still present
    @locks.compute(key) { |_, current| current.equal?(lock) ? nil : current }
  end
end
