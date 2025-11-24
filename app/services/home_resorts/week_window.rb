# app/services/home_resorts/week_window.rb
module HomeResorts
  class WeekWindow
    TZ = ActiveSupport::TimeZone["America/Denver"]

    # Returns [window_start_date, next_reset_at(TimeWithZone)]
    def self.current
      now = TZ.now
      # wday: 0=Sunday ... 6=Saturday
      days_from_sunday = now.wday # Sunday==0 (already our anchor)
      start_of_week = (now - days_from_sunday.days).beginning_of_day
      [ start_of_week.to_date, (start_of_week + 1.week) ]
    end
  end
end
