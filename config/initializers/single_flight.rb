# config/initializers/single_flight.rb
require Rails.root.join("app/lib/single_flight.rb")
SINGLE_FLIGHT = SingleFlight.new
