# app/controllers/admin/base_controller.rb
class Admin::BaseController < ApplicationController
  layout "admin"

  http_basic_authenticate_with(
    name:     ENV.fetch("ADMIN_USER"),
    password: ENV.fetch("ADMIN_PASSWORD")
  )
end
