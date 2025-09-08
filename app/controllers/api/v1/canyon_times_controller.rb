module Api
  module V1
    class CanyonTimesController < Api::V1::ApiController
      def resorts
        resorts = Resort.active
        json_resorts = ResortsContextPresenter.new(resorts).all_resorts
        render json: { resorts: json_resorts }
      end

      def times
        resort_id = params[:resort_id]
        resort = Resort.find_by(slug: resort_id)
        result = CottonwoodCanyons::TravelData.new(resort: resort).call

        render json: result
      end

      def travel_times
        resort_id = params[:resort_id]
        resort = Resort.find_by(slug: resort_id)
        result = CottonwoodCanyons::TravelTimes.new(resort: resort).call

        render json: result
      end

      def cameras
        resort_id = params[:resort_id]
        resort = Resort.find_by(slug: resort_id)
        result = Udot::Cameras.new(resort: resort).call

        render json: { cameras: result.value }
      end

      def featured_cameras
        resort_id = params[:resort_id]
        resort = Resort.find_by(slug: resort_id)
        result = Udot::FeaturedCameras.new(resort: resort).call

        render json: { cameras: result.value }
      end

      def parking_cameras
        resort_id = params[:resort_id]
        @resort = Resort.find_by(slug: resort_id)
        cameras = @resort.parking_cameras.map { |camera| camera.data }

        render json: { cameras: cameras }
      end

      def parking_profile
        resort_id = params[:resort_id]
        @resort = Resort.find_by(slug: resort_id)
        profile = @resort.parking_profiles.where(live: true).first

        render json: { profile: profile }
      end

      def signs
        resort_id = params[:resort_id]
        resort = Resort.find_by(slug: resort_id)
        result = Udot::Signs.new(resort: resort).call

        render json: { signs: result.value }
      end

      def alerts_events
        resort_id = params[:resort_id]
        resort = Resort.find_by(slug: resort_id)
        result = Udot::Warnings.new(resort: resort).call

        render json: { alerts_events: result.value }
      end

      def directions
        resort_id = params[:resort_id]
        resort = Resort.find_by(slug: resort_id)
        directions_data = CottonwoodCanyons::Google::Directions.new(origin: resort.departure_point, destination: resort.location).call

        render json: { routes: directions_data&.value }
      end
    end
  end
end
