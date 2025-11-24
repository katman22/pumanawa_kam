class Api::V1::MobileApiController < ActionController::API
  include AuthenticateMobileApi
  attr_accessor :formatted_results

  before_action :authenticate_api_request!

  NOT_FOUND = "Not Found"

  # protect_from_forgery with: :null_session

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: NOT_FOUND }, status: :not_found
  end

  def version_check
    min = Gem::Version.new(ENV["MIN_APP_VERSION"] || "0.0.0")

    current = Gem::Version.new(
      request.headers["X-App-Version"] || "0.0.0"
    )
    puts "Version: #{current}"
    render json: { ok: true }
    if current < min
      render json: {
        min_version: min.to_s,
        current_version: current.to_s,
        message: "A newer version of Canyon Traveller is required.",
        url: ios_or_android_store_url
      }, status: 426
    else
      render json: { ok: true }
    end
  end

  private

  def ios_or_android_store_url
    if request.headers["X-Platform"] == "ios"
      "https://apps.apple.com/app/id6752226942"
    else
      "https://play.google.com/store/apps/details?id=com.wharepumanawa.canyon_travel"
    end
  end

end
