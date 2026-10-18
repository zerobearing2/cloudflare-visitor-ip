module CloudflareVisitorIp
  class Railtie < Rails::Railtie
    config.cloudflare_visitor_ip = ActiveSupport::OrderedOptions.new
    config.cloudflare_visitor_ip.middleware = true

    initializer "cloudflare_visitor_ip.ipv6_prefix", after: :load_config_initializers do |app|
      if app.config.cloudflare_visitor_ip.key?(:ipv6_prefix)
        CloudflareVisitorIp.ipv6_prefix = app.config.cloudflare_visitor_ip.ipv6_prefix
      end
    end

    initializer "cloudflare_visitor_ip.middleware", after: :load_config_initializers do |app|
      if app.config.cloudflare_visitor_ip.middleware
        app.middleware.insert_after ActionDispatch::RemoteIp, CloudflareVisitorIp::Middleware
      end
    end
  end
end
