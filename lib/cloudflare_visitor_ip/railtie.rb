module CloudflareVisitorIp
  class Railtie < Rails::Railtie
    config.cloudflare_visitor_ip = ActiveSupport::OrderedOptions.new
    config.cloudflare_visitor_ip.middleware = true

    initializer "cloudflare_visitor_ip.middleware" do |app|
      app.middleware.insert_after ActionDispatch::RemoteIp, CloudflareVisitorIp::Middleware
    end

    initializer "cloudflare_visitor_ip.ipv6_prefix", after: :load_config_initializers do |app|
      if app.config.cloudflare_visitor_ip.key?(:ipv6_prefix)
        CloudflareVisitorIp.ipv6_prefix = app.config.cloudflare_visitor_ip.ipv6_prefix
      end
    end

    initializer "cloudflare_visitor_ip.middleware_off", after: :load_config_initializers do |app|
      app.middleware.delete CloudflareVisitorIp::Middleware unless app.config.cloudflare_visitor_ip.middleware
    end
  end
end
