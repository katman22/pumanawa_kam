# config/initializers/single_flight.rb
require Rails.root.join("lib/single_flight")
SINGLE_FLIGHT = SingleFlight.new