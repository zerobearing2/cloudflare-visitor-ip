require "test_helper"
require "fixtures/rails_app"
require "open3"

RailsApp.initialize!
RailsApp.routes.draw { root "visitors#show" }

# Production hops: visitor -> Cloudflare -> kamal-proxy -> Thruster -> Puma.
# kamal-proxy terminates TLS, drops the client's X-Forwarded-For and writes the
# peer that connected to it. Thruster appends kamal-proxy and connects to Puma
# over loopback. CF-Connecting-IP, which Cloudflare sets to the visitor, passes
# through both.
class VisitorAddressTest < ActiveSupport::TestCase
  CLOUDFLARE_EDGE = "172.71.10.20"
  CLOUDFLARE_EDGE_V6 = "2606:4700::10"
  KAMAL_PROXY = "172.18.0.2"
  OUTSIDER = "198.51.100.20"
  VISITOR = "203.0.113.7"
  VISITOR_V6 = "2001:db8::7"
  NEIGHBOR = "203.0.113.8"

  test "an IPv4 visitor behind a Cloudflare edge is known by their own address" do
    assert_equal VISITOR, remote_ip(from: CLOUDFLARE_EDGE, connecting_ip: VISITOR)
  end

  test "an IPv6 visitor behind an IPv6 Cloudflare edge is known by their own address" do
    assert_equal VISITOR_V6, remote_ip(from: CLOUDFLARE_EDGE_V6, connecting_ip: VISITOR_V6)
  end

  test "a Cloudflare edge that names no single address keeps the edge address" do
    [ nil, "", "unknown", "203.0.113.0/24", "2001:db8::/64", "#{VISITOR}, #{NEIGHBOR}" ].each do |connecting_ip|
      assert_equal CLOUDFLARE_EDGE, remote_ip(from: CLOUDFLARE_EDGE, connecting_ip: connecting_ip), "CF-Connecting-IP: #{connecting_ip.inspect}"
    end
  end

  test "a peer outside Cloudflare cannot choose its address with CF-Connecting-IP" do
    assert_equal OUTSIDER, remote_ip(from: OUTSIDER, connecting_ip: VISITOR)
    assert_equal KAMAL_PROXY, remote_ip(from: KAMAL_PROXY, connecting_ip: VISITOR)
  end

  test "the middleware runs after ActionDispatch::RemoteIp and before the request logger" do
    middleware = RailsApp.middleware.map(&:klass)

    assert_operator middleware.index(ActionDispatch::RemoteIp), :<, middleware.index(CloudflareVisitorIp::Middleware)
    assert_operator middleware.index(CloudflareVisitorIp::Middleware), :<, middleware.index(Rails::Rack::Logger)
  end

  test "the request log names the visitor, not the Cloudflare edge" do
    RailsApp::LOG.string = +""

    remote_ip(from: CLOUDFLARE_EDGE, connecting_ip: VISITOR)

    assert_includes RailsApp::LOG.string, %(Started GET "/" for #{VISITOR} )
    assert_not_includes RailsApp::LOG.string, CLOUDFLARE_EDGE
  end

  test "an app that turns the middleware off keeps the Cloudflare edge address" do
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", "-Itest", "-e", <<~RUBY)
      require "fixtures/rails_app"
      RailsApp.config.cloudflare_visitor_ip.middleware = false
      RailsApp.initialize!
      RailsApp.routes.draw { root "visitors#show" }
      env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "127.0.0.1", "HTTP_X_FORWARDED_FOR" => "#{CLOUDFLARE_EDGE}, #{KAMAL_PROXY}", "HTTP_CF_CONNECTING_IP" => "#{VISITOR}")
      print RailsApp.call(env).last.join
    RUBY

    assert status.success?, stderr
    assert_equal CLOUDFLARE_EDGE, JSON.parse(stdout)["remote_ip"]
  end

  private
    def remote_ip(from:, connecting_ip:)
      env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "127.0.0.1", "HTTP_X_FORWARDED_FOR" => "#{from}, #{KAMAL_PROXY}")
      env["HTTP_CF_CONNECTING_IP"] = connecting_ip unless connecting_ip.nil?
      status, _headers, body = RailsApp.call(env)
      assert_equal 200, status
      JSON.parse(body.each.to_a.join)["remote_ip"]
    end
end
