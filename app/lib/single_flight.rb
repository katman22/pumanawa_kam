# lib/single_flight.rb
class SingleFlight
  def initialize
    @locks = Concurrent::Map.new
  end

  def do(key)
    m = (@locks[key] ||= Mutex.new)
    m.synchronize { yield }
  ensure
    @locks.delete(key)
  end
end
