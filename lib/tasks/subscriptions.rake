namespace :subs do
  desc "Reconcile subscriptions with stores"
  task reconcile: :environment do
    User.find_each do |u|
      # TODO: Pull latest status via provider APIs, upsert, then:
      Entitlements::Resolver.call!(user: u)
    end
  end
end
