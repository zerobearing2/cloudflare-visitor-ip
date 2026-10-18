module CloudflareVisitorIp
  class Railtie < Rails::Railtie
    config.cloudflare_visitor_ip = ActiveSupport::OrderedOptions.new
    config.cloudflare_visitor_ip.middleware = true

    initializer "cloudflare_visitor_ip.middleware" do |app|
      if app.config.cloudflare_visitor_ip.middleware
        app.middleware.insert_after ActionDispatch::RemoteIp, CloudflareVisitorIp::Middleware
      end
    end
  end
end
