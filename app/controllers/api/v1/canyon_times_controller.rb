module Api
  module V1
    class CanyonTimesController < Api::V1::ApiController
      def times
        resort_id = params[:resort_id]
        resort = ResortContext.for(resort_id)
        result = CottonwoodCanyons::TravelData.new(resort: resort).call

        render json: result
      end

      def cameras
        resort_id = params[:resort_id]
        resort = ResortContext.for(resort_id)
        result = Udot::Cameras.new(resort: resort).call

        render json: { cameras: result.value }
      end

      def signs
        resort_id = params[:resort_id]
        resort = ResortContext.for(resort_id)
        result = Udot::Signs.new(resort: resort).call

        render json: { signs: result.value }
      end

      def alerts_events
        resort_id = params[:resort_id]
        resort = ResortContext.for(resort_id)
        result = Udot::Warnings.new(resort: resort).call

        render json: { alerts_events: result.value }
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
