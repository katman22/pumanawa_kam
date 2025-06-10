class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :set_browser, :set_locale

  def set_browser
    @browser = Browser.new(request.user_agent)
  end

  helper_method :mobile_device?

  def mobile_device?
    @browser.device.mobile?
  end

  def set_locale
    I18n.locale = params[:locale] || I18n.default_locale
  end

  def default_url_options
    { locale: I18n.locale }
  end
end
