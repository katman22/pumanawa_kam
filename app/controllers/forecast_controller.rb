class ForecastController < ApplicationController
  include BaseForecaster

  def index
    @erred, @locations, @total = find_locations(params[:location])
    return unless @locations&.size == 1
    locale = @locations.first
    @erred, @summary = summary_forecast_for_location(locale[:lat], locale[:lng])
  end

  def radar_for_locale_web
    @lat = params[:lat]
    @lng = params[:lng]
    location_data = params.permit(:lat, :location, :location_name, :country_code).to_h.merge("long" => @lng).with_indifferent_access
    recent_location = Array(session[:recent_locations]).find do |entry|
      entry = entry.with_indifferent_access
      @lat.present? && @lng.present? &&
        entry[:latitude].to_s == @lat.to_s && entry[:longitude].to_s == @lng.to_s &&
        entry[:location_name].present?
    end
    if recent_location
      recent_location = recent_location.with_indifferent_access
      %i[location location_name country_code].each do |key|
        location_data[key] = recent_location[key] if location_data[key].blank?
      end
    end
    @location_context = LocationContext.new(location_data)
    @type = params[:type] || DEFAULT_LAYER
    render layout: "map_web", locals: { type: @type, lng: @lng, lat: @lat }
  end

  def radar_webview
    @lat = params[:lat]
    @lng = params[:lng]
    @type = params[:type] || DEFAULT_LAYER
    render layout: "map_only", locals: { type: @type, lng: @lng, lat: @lat }
  end

  def radar_for_locale
    @lat = params[:lat]
    @lng = params[:lng]
    @type = params[:type] || DEFAULT_LAYER
    render layout: "map_only", locals: { type: @type, lng: @lng, lat: @lat }
  end

  def geo_location
    location = params[:location]
    erred, locations, total = location_services(location)
    multi_locations(locations: locations, total: total, erred: erred, location: location)
  end

  def summary
    location_context, _recent_locations = set_defaults
    erred, summary = summary_forecast_for_location(location_context.latitude, location_context.longitude)
    render partial: "forecast_summary", locals: { summary: summary, location: location_context.location, location_name: location_context.location_name, erred: erred }
  end

  def full
    @location_context, _recent_locations = set_defaults
    @erred, @forecasts = forecaster
    unless @erred
      load_full_discussion
      load_full_alerts
    end
  end

  def dual_full
    target = params[:turbo_location]
    return head :unprocessable_entity unless dual_target?(target)

    context = LocationContext.new(params)
    load_dual_forecast(target, context)
  end

  def text_only
    @location_context, _recent_locations = set_defaults
    @erred, @forecasts = forecaster
  end

  def multi_locations(locations:, total:, erred:, location:)
    render turbo_stream: [
      turbo_stream.replace("summary_response", partial: "clear"),
      turbo_stream.replace("location_response", partial: "geo_location", locals: { location: location, locations: locations, total: total, erred: erred })
    ]
  end

  def dual
    @recent_locations = session[:recent_locations]
  end

  def dual_geo_location
    target = { SCREEN_A => "location_response_a", SCREEN_B => "location_response_b" }[params[:commit]]
    return head :unprocessable_entity unless dual_target?(target)

    erred, locations, total = location_services(params[:location])
    return full_forecast_for_location(target, locations.first) if !erred && total == 1

    dual_multi_locations(target, params[:location], locations, total, erred)
  rescue StandardError => error
    Rails.logger.warn("Dual location unavailable: #{error.class}: #{error.message}")
    dual_multi_locations(target, params[:location], [], 0, true)
  end

  def dual_multi_locations(turbo_location, location, locations, total, erred)
    render turbo_stream: [
      turbo_stream.replace(
        turbo_location, partial: "geo_location_dual",
        locals: { location: location, locations: locations, total: total, erred: erred, turbo_location: turbo_location })
    ]
  end

  def full_forecast_for_location(turbo_location, found_location)
    found_location = found_location.with_indifferent_access
    context = LocationContext.new(
      lat: found_location[:lat], long: found_location[:lng],
      location: params[:location], location_name: found_location[:name],
      country_code: found_location[:country_code]
    )
    load_dual_forecast(turbo_location, context)
  end

  def render_forecast(turbo_location, forecasts, erred, location_context)
    render turbo_stream: [
      turbo_stream.replace(
        turbo_location, partial: "dual_full",
        locals: { forecasts: forecasts, erred: erred, turbo_location: turbo_location, location_context: location_context })
    ]
  end

  private

  def dual_target?(target)
    %w[location_response_a location_response_b].include?(target)
  end

  def load_dual_forecast(target, context)
    unless context.latitude.present? && context.longitude.present? && context.country_code.present?
      return render_forecast(target, "Location coordinates and country are required. Please search again.", true, context)
    end

    RecentLocations.new(session).add(context.to_h.stringify_keys)
    erred, forecasts = forecaster(context)
    render_forecast(target, forecasts, erred, context)
  rescue StandardError => error
    Rails.logger.warn("Dual forecast unavailable: #{error.class}: #{error.message}")
    render_forecast(target, "Forecast is currently unavailable. Please try again.", true, context)
  end

  def load_full_alerts
    @alerts_available = false
    @alerts = []
    erred, result = create_alert_forecasts(
      latitude: @location_context.latitude,
      longitude: @location_context.longitude,
      country_code: @location_context.country_code
    )
    return if erred

    @alerts = result.value.fetch("alerts", [])
    @alerts_available = true
  rescue StandardError => error
    Rails.logger.warn("Forecast alerts unavailable: #{error.class}: #{error.message}")
  end

  def load_full_discussion
    erred, result = forecast_discussion(
      latitude: @location_context.latitude,
      longitude: @location_context.longitude,
      country_code: @location_context.country_code
    )
    @discussion = result.value unless erred
  rescue StandardError => error
    Rails.logger.warn("Forecast discussion unavailable: #{error.class}: #{error.message}")
  end

  def forecaster(context = @location_context)
    results = create_forecasts(latitude: context.latitude, longitude: context.longitude, country_code: context.country_code)
    return results if results.first

    forecasts = context.country_code == "us" ? results.last["forecasts"] : results.last
    [ results.first, forecasts ]
  end
end
