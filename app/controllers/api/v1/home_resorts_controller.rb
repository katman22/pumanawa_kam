# app/controllers/api/v1/home_resorts_controller.rb
class Api::V1::HomeResortsController < Api::V1::MobileApiController
  SUBSCRIBED_CAP = { "free" => 0, "standard" => 2, "pro" => 4, "premium" => :all }.freeze
  FREE_CAP = { "free" => 2, "standard" => 2, "pro" => 2, "premium" => 2 }.freeze

  def index
    eff = resolve_entitlements!

    # 👇 Add this before reading any existing home resort selections
    maybe_clear_expired_home_resorts!(eff)

    # ensure/change window info (does NOT change any selections)
    cw = HomeResorts::ChangeLimiter.remaining_for(current_user, eff.value[:tier])

    subs = HomeResort.for_user(current_user).subscribed_only.joins(:resort).pluck("resorts.slug")
    free = HomeResort.for_user(current_user).free_only.joins(:resort).pluck("resorts.slug")

    subs_cap = cap_for(SUBSCRIBED_CAP, eff.value[:tier])
    free_cap = cap_for(FREE_CAP, eff.value[:tier])

    render json: {
      subscribed_slugs: subs,
      free_slugs: free,
      limits: {
        subscribed: subs_cap == :all ? "all" : subs_cap,
        free: free_cap
      },
      remaining: {
        subscribed: subs_cap == :all ? "all" : [subs_cap - subs.size, 0].max,
        free: [free_cap - free.size, 0].max
      },
      change_window: {
        remaining_changes: cw[:remaining] == Float::INFINITY ? "unlimited" : cw[:remaining],
        next_reset_at_mst_iso: cw[:next_reset_at_mst].iso8601
      }
    }
  end

  def update
    eff = resolve_entitlements!

    subs_slugs = Array(params[:subscribed_slugs]).map!(&:to_s).uniq
    free_slugs = Array(params[:free_slugs]).map!(&:to_s).uniq

    overlap = subs_slugs & free_slugs
    if overlap.any?
      return render json: { error: "A resort cannot be both subscribed and free: #{overlap.join(', ')}" },
                    status: :unprocessable_entity
    end

    subs_ids = Resort.where(slug: subs_slugs).pluck(:id, :slug)
    free_ids = Resort.where(slug: free_slugs).pluck(:id, :slug)

    missing = (subs_slugs - subs_ids.map(&:last)) + (free_slugs - free_ids.map(&:last))
    if missing.any?
      return render json: { error: "Unknown resort slugs: #{missing.uniq.join(', ')}" },
                    status: :unprocessable_entity
    end

    subs_cap = cap_for(SUBSCRIBED_CAP, eff.value[:tier])
    free_cap = cap_for(FREE_CAP, eff.value[:tier])

    if subs_cap != :all && subs_ids.size > subs_cap
      return render json: { error: "Too many subscribed home resorts for your plan" },
                    status: :unprocessable_entity
    end
    if free_ids.size > free_cap
      return render json: { error: "Too many free home resorts for your plan" },
                    status: :unprocessable_entity
    end

    current_subs = HomeResort.for_user(current_user).subscribed_only.joins(:resort).pluck("resorts.slug").sort
    current_free = HomeResort.for_user(current_user).free_only.joins(:resort).pluck("resorts.slug").sort
    requested_subs = subs_ids.map(&:last).sort
    requested_free = free_ids.map(&:last).sort

    changed = (current_subs != requested_subs) || (current_free != requested_free)

    if changed
      cw = HomeResorts::ChangeLimiter.remaining_for(current_user, eff.value[:tier])
      if cw[:remaining] != Float::INFINITY && cw[:remaining] <= 0
        return render json: {
          error: "No changes remaining until #{cw[:next_reset_at_mst].iso8601} MST"
        }, status: :unprocessable_entity
      end
    end

    ActiveRecord::Base.transaction do
      HomeResort.for_user(current_user).delete_all
      subs_ids.each { |rid, _| HomeResort.create!(user_id: current_user.id, resort_id: rid, kind: :subscribed) }
      free_ids.each { |rid, _| HomeResort.create!(user_id: current_user.id, resort_id: rid, kind: :free) }

      HomeResorts::ChangeLimiter.consume!(current_user, eff.value[:tier], by: 1) if changed
    end

    head :no_content
  rescue => e
    Rails.logger.error("HomeResorts#update error: #{e.class}: #{e.message}")
    render json: { error: "Internal error" }, status: :internal_server_error
  end

  private

  # -----------------------------------------------------
  # NEW: Auto-clear home resorts after subscription loss
  # -----------------------------------------------------
  def maybe_clear_expired_home_resorts!(eff)
    # If user still has an active subscription tier, leave everything as-is
    return if eff.value[:tier] != "free"

    # Last time the user changed home resorts
    last_change = HomeResort.for_user(current_user).maximum(:updated_at)

    # Last time any subscription became inactive
    last_expired = current_user.subscriptions.where(status: "inactive").maximum(:updated_at)

    # Nothing to compare → skip
    return unless last_expired && last_change

    # Only clear if subscription expired *after* last resort selection
    return unless last_expired > last_change

    Rails.logger.info(
      "[HomeResorts] Auto-clearing home resorts for user=#{current_user.id} " \
        "due to subscription expiry @ #{last_expired}"
    )

    HomeResort.for_user(current_user).delete_all
    HomeResorts::ChangeLimiter.reset!(current_user, eff.value[:tier])
  end

  def resolve_entitlements!
    eff = Entitlements::Resolver.call(user: current_user)
    unless eff.success?
      Rails.logger.warn("Entitlements resolver failed for user #{current_user.id}: #{eff.error}")
      render json: { error: "Entitlements unavailable" }, status: :service_unavailable
      throw :halt
    end
    eff
  end

  def cap_for(map, tier)
    map.fetch(tier) { 0 }
  end
end
