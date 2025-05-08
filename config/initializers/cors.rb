Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Use "*" only in development
    origins do
      ENV.fetch("CORS_ALLOWED_ORIGINS")
    end

    resource "*",
             headers: :any,
             methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
             expose: [ "Authorization" ]
  end
end
