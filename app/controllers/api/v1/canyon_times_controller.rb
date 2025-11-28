# app/controllers/api/v1/canyon_times_controller.rb
module Api
  module V1
    class CanyonTimesController < Api::V1::MobileApiController
      def resorts
        resorts = Resort.active
        json_resorts = ResortsContextPresenter.new(resorts).all_resorts
        # small cache on the whole payload (it’s basically static during the day)
        expires_in 60.seconds, public: true
        render json: { resorts: json_resorts }
      end

      def times
        resort = Resort.find_by(slug: params[:resort_id])
        return render json: { error: "Resort not found" }, status: :not_found if resort.nil?

        type   = params[:type].presence_in(%w[all to from]) || "all"
        result = CottonwoodCanyons::TravelData.new(resort: resort, type: type).call
        render json: result
      end

      # DEPRECATED: keep endpoint but delegate to #times so we never do extra work.
      def travel_times
        resort_id = params[:resort_id]
        resort = Resort.find_by(slug: resort_id)
        resort = Resort.find_by(slug: params[:resort_id])
        result = CottonwoodCanyons::TravelTimes.new(resort: resort).call

        render json: result
      end

      def cameras
        resort = Resort.find_by(slug: params[:resort_id])
        result = Udot::Cameras.new(resort: resort).call
        render json: { cameras: result.value }
      end

      def featured_cameras
        resort = Resort.find_by(slug: params[:resort_id])
        result = Udot::FeaturedCameras.new(resort: resort).call
        render json: { cameras: result.value }
      end

      def parking_cameras
        resort = Resort.find_by(slug: params[:resort_id])
        cameras = resort.parking_cameras.map { |camera| camera.data }
        render json: { cameras: cameras }
      end

      def parking_profile
        resort = Resort.find_by(slug: params[:resort_id])
        profile = resort.parking_profiles.where(live: true).first
        render json: { profile: profile }
      end

      def signs
        resort = Resort.find_by(slug: params[:resort_id])
        result = Udot::Signs.new(resort: resort).call
        render json: { signs: result.value }
      end

      def alerts_events
        resort = Resort.find_by(slug: params[:resort_id])
        result = Udot::Warnings.new(resort: resort).call
        render json: { alerts_events: result.value }
      end

      def directions
        resort = Resort.find_by(slug: params[:resort_id])
        directions_data = CottonwoodCanyons::Google::Directions.new(
          origin: resort.departure_point,
          destination: resort.location
        ).call
        render json: { routes: directions_data&.value }
      end
    end
  end
end
