module Api
  module V1
    class CanyonTimesController < Api::V1::ApiController
      def times
        resort_id = params[:resort_id]
        resort = ResortContext.for(resort_id)
        result = CottonwoodCanyons::TravelData.new(resort: resort).call

        render json: result
      end

      def directions
        resort_id = params[:resort_id]
        resort = ResortContext.for(resort_id)
        directions_data = CottonwoodCanyons::Google::Directions.new(origin: resort.departure_point, destination: resort.location).call

        render json: { routes: directions_data&.value }
      end
    end
  end
end
