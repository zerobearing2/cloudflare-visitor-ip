ENV["RAILS_ENV"] = "test"
require "bundler/setup"
require "rails"
require "action_controller/railtie"
Bundler.require

class RailsApp < Rails::Application
  LOG = StringIO.new

  config.root = __dir__
  config.eager_load = false
  config.secret_key_base = "cloudflare-visitor-ip"
  config.logger = ActiveSupport::Logger.new(LOG)
  config.log_level = :info
end

class VisitorsController < ActionController::Base
  def show
    render json: { remote_ip: request.remote_ip }
  end
end
