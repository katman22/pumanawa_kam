module VersionGate
  extend ActiveSupport::Concern

  included do
    before_action :enforce_minimum_version
  end

  private

  def enforce_minimum_version
    client = request.headers["X-App-Version"].to_s
    server_min = ENV.fetch("MIN_APP_VERSION", "1.0.0")

    return if client.blank?  # allow old debug/dev
    return if version_gte?(client, server_min)

    render json: {
      error: "update_required",
      current: client,
      minimum: server_min,
      url: update_url_for_platform
    }, status: :forbidden
  end

  def version_gte?(client, min)
    c = client.split(".").map(&:to_i)
    m = min.split(".").map(&:to_i)

    c <=> m >= 0
  end

  def update_url_for_platform
    if request.user_agent&.include?("iPhone")
      "https://apps.apple.com/app/id6752226942"
    else
      "https://play.google.com/store/apps/details?id=com.wharepumanawa.canyon_travel"
    end
  end
end
