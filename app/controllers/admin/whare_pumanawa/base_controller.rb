class Admin::WharePumanawa::BaseController < Admin::BaseController
  before_action :require_mural_admin!
end
