# app/controllers/api/v1/home_resorts_controller.rb
class Api::V1::HomeResortsController < Api::V1::MobileApiController
  # Caps per tier (no weekly limits, just selection caps)
  CAPS = {
    "free"     => { subscribed: 0,     free: 2 },
    "standard" => { subscribed: 2,     free: 2 },
    "pro"      => { subscribed: 4,     free: 2 },
    "premium"  => { subscribed: "all", free: 2 } # or free: "all" later if you like
  }.freeze

  # GET /api/v1/home_resorts
  def index
    eff  = Entitlements::Resolver.call(user: current_user)
    tier = eff.value[:tier] || "free"
    caps = CAPS.fetch(tier, CAPS["free"])
    homes = HomeResort.for_user(current_user).includes(:resort)

    subscribed_slugs = []
    free_slugs       = []

    homes.each do |hr|
      slug = hr.resort&.slug
      next unless slug

      case hr.kind.to_s
      when "subscribed"
        subscribed_slugs << slug
      when "free"
        free_slugs << slug
      end
    end

    subscribed_slugs.uniq!
    free_slugs.uniq!

    render json: {
      subscribed_slugs: subscribed_slugs,
      free_slugs:       free_slugs,
      limits:           caps,
      # No weekly gating: "remaining" == caps
      remaining:        caps
    }
  end

  # PUT /api/v1/home_resorts
  def update
    eff     = Entitlements::Resolver.call(user: current_user)
    tier    = eff.value[:tier] || "free"
    active  = eff.value[:active]
    caps    = CAPS.fetch(tier, CAPS["free"])

    # Has this user ever had a paid subscription?
    was_paid_before = Subscription.where(user_id: current_user.id)
                                  .where(status: %w[active in_grace on_hold expired])
                                  .where.not(product_id: nil)
                                  .exists?

    # If user was paid before, and is now effectively "free + inactive", wipe
    if was_paid_before && tier == "free" && !active
      HomeResort.for_user(current_user).delete_all
      return render json: {
        subscribed_slugs: [],
        free_slugs: [],
        limits: CAPS["free"],
        remaining: CAPS["free"]
      }
    end

    # Arrays of slugs from the client
    subs  = Array(params[:subscribed_slugs]).map(&:to_s).uniq
    frees = Array(params[:free_slugs]).map(&:to_s).uniq

    # Load current state to detect no-op updates
    current_homes = HomeResort.for_user(current_user).includes(:resort)

    current_subs = []
    current_frees = []

    current_homes.each do |hr|
      case hr.kind.to_s
      when "subscribed" then current_subs << hr.resort.slug
      when "free"       then current_frees << hr.resort.slug
      end
    end

    # ✨ EARLY RETURN for no-op updates
    if current_subs.sort == subs.sort && current_frees.sort == frees.sort
      return render json: {
        subscribed_slugs: current_subs,
        free_slugs:       current_frees,
        limits:           caps,
        remaining:        caps
      }
    end

    # Cannot be both favorite and free
    overlap = subs & frees
    if overlap.any?
      return render json: { error: "A resort cannot be both favorite and free." },
                    status: :unprocessable_entity
    end

    # Cap checks (only if data actually changed)
    unless caps[:subscribed] == "all" || subs.size <= caps[:subscribed].to_i
      return render json: { error: "Too many favorite resorts for your tier." },
                    status: :unprocessable_entity
    end

    unless frees.size <= caps[:free].to_i
      return render json: { error: "Too many free resorts for your tier." },
                    status: :unprocessable_entity
    end

    # Map slugs -> IDs
    slugs = (subs + frees).uniq
    resorts_by_slug = Resort.where(slug: slugs).pluck(:slug, :id).to_h

    missing = slugs - resorts_by_slug.keys
    if missing.any?
      return render json: { error: "Unknown resort slugs: #{missing.join(', ')}" },
                    status: :unprocessable_entity
    end

    subs_ids = subs.map  { |slug| resorts_by_slug[slug] }
    free_ids = frees.map { |slug| resorts_by_slug[slug] }

    if subs.empty? && frees.empty?
      # Do NOT clear the user’s homes unless explicitly sent by user action
      return render json: {
        subscribed_slugs: current_subs,
        free_slugs: current_frees,
        limits: caps,
        remaining: caps
      }
    end

    ActiveRecord::Base.transaction do
      HomeResort.for_user(current_user).delete_all

      subs_ids.each do |rid|
        HomeResort.create!(
          user_id:   current_user.id,
          resort_id: rid,
          kind:      :subscribed
        )
      end

      free_ids.each do |rid|
        HomeResort.create!(
          user_id:   current_user.id,
          resort_id: rid,
          kind:      :free
        )
      end
    end

    render json: {
      subscribed_slugs: subs,
      free_slugs:       frees,
      limits:           caps,
      remaining:        caps
    }
  end
end
