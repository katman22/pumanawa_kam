# frozen_string_literal: true

class RecentLocations
  attr_reader :session

  def initialize(session)
    @session = session
    session[:recent_locations] ||= []
  end

  def add(location_data)
    session[:recent_locations].unshift(location_data)
    session[:recent_locations].uniq!
    session[:recent_locations] = session[:recent_locations].take(12)
  end

  def list
    session[:recent_locations]
  end
end
