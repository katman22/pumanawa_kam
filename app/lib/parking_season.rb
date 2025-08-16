module ParkingSeason
  # Returns e.g. "2025-26"
  def self.current(today: Time.zone.today)
    year = today.year
    # Season runs roughly Nov -> May; Aug-Oct are considered the *upcoming* season
    start_year =
      if today.month >= 8 # Aug-Dec: upcoming season starting this calendar year
        year
      else                # Jan-Jul: season that started last year
        year - 1
      end
    "#{start_year}-#{(start_year + 1).to_s[-2..-1]}"
  end

  # Defaults: Nov 1 -> May 15 for that season
  def self.default_window(season)
    start_year = season.split("-").first.to_i
    [
      Time.zone.parse("#{start_year}-11-01"),
      Time.zone.parse("#{start_year + 1}-05-31")
    ]
  end
end
