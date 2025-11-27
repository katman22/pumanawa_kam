class Api::V1::HomeResortsController < Api::V1::MobileApiController
  CAPS = {
    "free"     => { subscribed: 0,     free: 2 },
    "standard" => { subscribed: 2,     free: 2 },
    "pro"      => { subscribed: 4,     free: 2 },
    "premium"  => { subscribed: "all", free: 2 }
  }.freeze

  # ------------------------
  # GET /home_resorts
  # ------------------------
  def index
    eff  = Entitlements::Resolver.call(user: current_user)
    tier = eff.value[:tier]
    caps = CAPS.fetch(tier, CAPS["free"])

    homes = HomeResort.for_user(current_user).includes(:resort)

    subscribed_slugs = homes.select { |h| h.kind == "subscribed" }.map { |h| h.resort.slug }
    free_slugs       = homes.select { |h| h.kind == "free" }.map { |h| h.resort.slug }

    render json: {
      subscribed_slugs: subscribed_slugs.uniq,
      free_slugs:       free_slugs.uniq,
      limits:           caps,
      remaining:        caps # no weekly gating
    }
  end

  # ------------------------
  # PUT /home_resorts
  # ------------------------
  def update
    eff  = Entitlements::Resolver.call(user: current_user)
    tier = eff.value[:tier]
    caps = CAPS.fetch(tier, CAPS["free"])

    subs_requested  = Array(params[:subscribed_slugs]).map(&:to_s).uniq
    free_requested  = Array(params[:free_slugs]).map(&:to_s).uniq

    # Cannot appear in both lists
    overlap = subs_requested & free_requested
    if overlap.any?
      return render json: { error: "A resort cannot be both favorite and free." },
                    status: :unprocessable_entity
    end

    # Cap enforcement
    unless caps[:subscribed] == "all" || subs_requested.count <= caps[:subscribed]
      return render json: { error: "Too many favorite resorts for your tier." }, status: :unprocessable_entity
    end

    unless free_requested.count <= caps[:free]
      return render json: { error: "Too many free resorts for your tier." }, status: :unprocessable_entity
    end

    # Convert slugs to IDs
    all_slugs = subs_requested + free_requested
    slug_map = Resort.where(slug: all_slugs).pluck(:slug, :id).to_h

    missing = all_slugs - slug_map.keys
    if missing.any?
      return render json: { error: "Unknown resort slugs: #{missing.join(', ')}" },
                    status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      HomeResort.for_user(current_user).delete_all

      subs_requested.each do |slug|
        HomeResort.create!(
          user_id: current_user.id,
          resort_id: slug_map[slug],
          kind: :subscribed
        )
      end

      free_requested.each do |slug|
        HomeResort.create!(
          user_id: current_user.id,
          resort_id: slug_map[slug],
          kind: :free
        )
      end
    end

    render json: {
      subscribed_slugs: subs_requested,
      free_slugs:       free_requested,
      limits:           caps,
      remaining:        caps
    }
  end
end
