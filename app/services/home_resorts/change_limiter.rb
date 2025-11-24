# app/services/home_resorts/change_limiter.rb
module HomeResorts
  class ChangeLimiter
    TZ = "America/Denver"
    PER_WEEK = {
      "free" => 1,
      "standard" => 2,
      "pro" => 4,
      "premium" => Float::INFINITY
    }.freeze

    def self.allowed_for(tier)
      PER_WEEK.fetch(tier.to_s, 1)
    end

    def self.ensure_window!(user, current_tier)
      tz = ActiveSupport::TimeZone[TZ]
      now = tz.now
      wk0 = now.beginning_of_week(:sunday)

      # (Re)start a new window if missing or stale
      if user.home_resort_window_start.nil? || user.home_resort_window_start < wk0
        allowed = allowed_for(current_tier)
        user.update_columns(
          home_resort_window_start: wk0.utc,
          home_resort_changes_remaining: (allowed.finite? ? allowed.to_i : nil) # nil = unlimited
        )
      end
    end

    def self.remaining_for(user, current_tier)
      ensure_window!(user, current_tier)
      rem = user.home_resort_changes_remaining
      rem = Float::INFINITY if rem.nil? # nil means unlimited

      tz = ActiveSupport::TimeZone[TZ]
      window_mst = user.home_resort_window_start.in_time_zone(tz)
      next_reset = (window_mst + 1.week).change(sec: 0)

      { remaining: rem, next_reset_at_mst: next_reset }
    end

    def self.consume!(user, current_tier, by: 1)
      ensure_window!(user, current_tier)
      return Float::INFINITY if allowed_for(current_tier) == Float::INFINITY

      new_val = [ user.home_resort_changes_remaining.to_i - by, 0 ].max
      user.update_columns(home_resort_changes_remaining: new_val)
      new_val
    end

    def self.reset!(user, current_tier)
      tz = ActiveSupport::TimeZone[TZ]
      now = tz.now
      wk0 = now.beginning_of_week(:sunday)

      allowed = allowed_for(current_tier)
      user.update_columns(
        home_resort_window_start: wk0.utc,
        home_resort_changes_remaining: (allowed.finite? ? allowed.to_i : nil)
      )
    end
  end
end
