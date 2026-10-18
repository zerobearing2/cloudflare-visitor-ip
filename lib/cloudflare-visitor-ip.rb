require "rails"
require "action_dispatch"
require_relative "cloudflare_visitor_ip"
require_relative "cloudflare_visitor_ip/middleware"
require_relative "cloudflare_visitor_ip/railtie"
require_relative "cloudflare_visitor_ip/remote_network"

ActiveSupport.on_load(:action_dispatch_request) { include CloudflareVisitorIp::RemoteNetwork }
