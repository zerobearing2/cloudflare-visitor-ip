module CloudflareVisitorIp
  class Railtie < Rails::Railtie
    config.cloudflare_visitor_ip = ActiveSupport::OrderedOptions.new
    config.cloudflare_visitor_ip.middleware = true
    config.cloudflare_visitor_ip.ipv6_prefix = CloudflareVisitorIp.ipv6_prefix

    initializer "cloudflare_visitor_ip.ipv6_prefix" do |app|
      CloudflareVisitorIp.ipv6_prefix = app.config.cloudflare_visitor_ip.ipv6_prefix
    end

    initializer "cloudflare_visitor_ip.middleware" do |app|
      if app.config.cloudflare_visitor_ip.middleware
        app.middleware.insert_after ActionDispatch::RemoteIp, CloudflareVisitorIp::Middleware
      end
    end
  end
end
