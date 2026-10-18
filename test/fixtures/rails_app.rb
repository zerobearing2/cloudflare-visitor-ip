ENV["RAILS_ENV"] = "test"
require "bundler/setup"
require "rails"
require "action_controller/railtie"
Bundler.require

class RailsApp < Rails::Application
  LOG = StringIO.new
  KAMAL_PROXY = "172.18.0.2"

  config.root = __dir__
  config.eager_load = false
  config.secret_key_base = "cloudflare-visitor-ip"
  config.logger = ActiveSupport::Logger.new(LOG)
  config.log_level = :info
  config.action_dispatch.show_exceptions = :none

  def self.boot
    initialize!
    routes.draw { root "visitors#show" }
  end

  # Production hops: visitor -> Cloudflare -> kamal-proxy -> Thruster -> Puma.
  # kamal-proxy terminates TLS, drops the client's X-Forwarded-For and writes the
  # peer that connected to it. Thruster appends kamal-proxy and connects to Puma
  # over loopback. CF-Connecting-IP, which Cloudflare sets to the visitor, passes
  # through both, as does the CF-Worker header Cloudflare adds to a Worker's fetch.
  def self.visit(from:, connecting_ip:, worker: nil)
    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "127.0.0.1", "HTTP_X_FORWARDED_FOR" => "#{from}, #{KAMAL_PROXY}")
    env["HTTP_CF_CONNECTING_IP"] = connecting_ip unless connecting_ip.nil?
    env["HTTP_CF_WORKER"] = worker unless worker.nil?
    _status, _headers, body = call(env)
    JSON.parse(body.each.to_a.join)
  end
end

class VisitorsController < ActionController::Base
  def show
    render json: { remote_ip: request.remote_ip, remote_network: request.remote_network }
  end
end
