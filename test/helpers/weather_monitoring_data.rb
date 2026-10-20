# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "minitest/autorun"
require "mocha/minitest"
require "ostruct"

module WeatherMonitoringData
  ANCHOR = Time.iso8601("2026-10-20T16:43:08Z")

  def fixture(name)
    JSON.parse(File.read(Rails.root.join("test/fixtures/files/noaa/#{name}.json")))
  end

  def normalized(raw = fixture("brighton_grid"))
    result = WeatherMonitoring::NormalizeForecast.call(raw: raw)
    assert result.success?, result.value.inspect
    result.value
  end

  def snapshot(data = normalized, at: ANCHOR)
    result = WeatherMonitoring::ForecastSnapshot.call(normalized: data, evaluation_at: at)
    assert result.success?, result.value.inspect
    result.value
  end

  def forecast(amount: 0, onset: ANCHOR + 3.days)
    raw = fixture("brighton_grid")
    raw["properties"]["updateTime"] = (ANCHOR - 1.hour).iso8601
    raw["properties"]["snowfallAmount"]["values"] = Array.new(24) do |i|
      start = ANCHOR + i * 6.hours
      { "validTime" => "#{start.iso8601}/PT6H", "value" => start == onset ? amount : 0 }
    end
    raw["properties"]["weather"]["values"] = [ { "validTime" => "#{ANCHOR.iso8601}/P6D", "value" => [ { "weather" => nil } ] } ]
    normalized(raw)
  end

  def http_response(body = nil, code: 200, headers: {}, **fields)
    body = fields if body.nil?
    OpenStruct.new(code: code, headers: headers, body: body.is_a?(String) ? body : JSON.generate(body))
  end

  def pilot_resort
    Resort.create!(resort_name: "Weather pilot test", slug: "brighton", latitude: 40.5986, longitude: -111.5845)
  end
end
