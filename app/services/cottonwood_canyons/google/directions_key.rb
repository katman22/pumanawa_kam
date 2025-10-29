# app/services/cottonwood_canyons/google/directions_key.rb
module CottonwoodCanyons
  module Google
    module DirectionsKey
      module_function

      def key_for(origin, destination, traffic_model: "best_guess", mode: "driving")
        o = normalize(origin)
        d = normalize(destination)
        "google_directions:o:#{o}:d:#{d}:tm:#{traffic_model}:m:#{mode}"
      end

      def normalize(v)
        v.to_s.strip.downcase.gsub(/\s+/, " ")
      end
    end
  end
end
