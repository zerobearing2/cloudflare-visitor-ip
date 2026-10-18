require "test_helper"
require "fixtures/rails_app"
require "open3"
require "tmpdir"

RailsApp.boot

class VisitorAddressTest < ActiveSupport::TestCase
  CLOUDFLARE_EDGE = "172.71.10.20"
  CLOUDFLARE_EDGE_V6 = "2606:4700::10"
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

  test "a visitor behind a Cloudflare edge written as IPv4-mapped IPv6 is known by their own address" do
    assert_equal VISITOR, remote_ip(from: "::ffff:#{CLOUDFLARE_EDGE}", connecting_ip: VISITOR)
  end

  test "an IPv4 visitor that CF-Connecting-IP writes as IPv4-mapped IPv6 is known by their IPv4 address" do
    assert_equal VISITOR, remote_ip(from: CLOUDFLARE_EDGE, connecting_ip: "::ffff:#{VISITOR}")
  end

  test "a Cloudflare edge that names no single address keeps the edge address" do
    [ nil, "", "unknown", "203.0.113.0/24", "2001:db8::/64", "#{VISITOR}, #{NEIGHBOR}" ].each do |connecting_ip|
      assert_equal CLOUDFLARE_EDGE, remote_ip(from: CLOUDFLARE_EDGE, connecting_ip: connecting_ip), "CF-Connecting-IP: #{connecting_ip.inspect}"
    end
  end

  test "a peer outside Cloudflare cannot choose its address with CF-Connecting-IP" do
    assert_equal OUTSIDER, remote_ip(from: OUTSIDER, connecting_ip: VISITOR)
    assert_equal RailsApp::KAMAL_PROXY, remote_ip(from: RailsApp::KAMAL_PROXY, connecting_ip: VISITOR)
  end

  test "a Worker's fetch is known by its Cloudflare edge, whatever CF-Connecting-IP the Worker set" do
    assert_equal CLOUDFLARE_EDGE, remote_ip(from: CLOUDFLARE_EDGE, connecting_ip: VISITOR, worker: "attacker.example")
  end

  test "remote_network is an IPv4 visitor's own address as a /32" do
    assert_equal "#{VISITOR}/32", RailsApp.visit(from: CLOUDFLARE_EDGE, connecting_ip: VISITOR)["remote_network"]
  end

  test "remote_network is the /32 of an IPv4 peer written as IPv4-mapped IPv6" do
    assert_equal "#{OUTSIDER}/32", RailsApp.visit(from: "::ffff:#{OUTSIDER}", connecting_ip: nil)["remote_network"]
  end

  test "remote_network is an IPv6 visitor's /64 by default, so rotating within it keeps one network" do
    networks = [ VISITOR_V6, "2001:db8::ffff:ffff:ffff:ffff", "2001:db8:0:1::7" ].map do |connecting_ip|
      RailsApp.visit(from: CLOUDFLARE_EDGE_V6, connecting_ip: connecting_ip)["remote_network"]
    end

    assert_equal [ "2001:db8::/64", "2001:db8::/64", "2001:db8:0:1::/64" ], networks
  end

  test "an app that sets ipv6_prefix to 56 counts every /64 inside one /56 as one network" do
    visits = visit_booted_app("RailsApp.config.cloudflare_visitor_ip.ipv6_prefix = 56",
      from: CLOUDFLARE_EDGE_V6, connecting_ips: [ "2001:db8:0:1::7", "2001:db8:0:ff::7", "2001:db8:0:100::7" ])

    assert_equal [ "2001:db8::/56", "2001:db8::/56", "2001:db8:0:100::/56" ], visits.map { |visit| visit["remote_network"] }
    assert_equal "2001:db8:0:1::7", visits.first["remote_ip"]
  end

  test "an app that sets the gem's config in config/initializers gets those settings" do
    visits = visit_app_with_initializer(<<~RUBY, from: CLOUDFLARE_EDGE_V6, connecting_ips: [ VISITOR_V6 ])
      Rails.application.config.cloudflare_visitor_ip.ipv6_prefix = 48
      Rails.application.config.cloudflare_visitor_ip.middleware = false
    RUBY

    assert_equal CLOUDFLARE_EDGE_V6, visits.sole["remote_ip"]
    assert_equal "2606:4700::/48", visits.sole["remote_network"]
  end

  test "an app that sets CloudflareVisitorIp.ipv6_prefix in config/initializers keeps that prefix" do
    visits = visit_app_with_initializer("CloudflareVisitorIp.ipv6_prefix = 48", from: CLOUDFLARE_EDGE_V6, connecting_ips: [ VISITOR_V6 ])

    assert_equal "2001:db8::/48", visits.sole["remote_network"]
  end

  test "an app with an ipv6_prefix outside 1 to 128 fails to boot" do
    [ "0", "129", '"56"' ].each do |prefix|
      _stdout, stderr, status = run_app("RailsApp.config.cloudflare_visitor_ip.ipv6_prefix = #{prefix}")

      assert_not status.success?, prefix
      assert_match(/ArgumentError.*config\.cloudflare_visitor_ip\.ipv6_prefix/, stderr, prefix)
    end
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
    visits = visit_booted_app("RailsApp.config.cloudflare_visitor_ip.middleware = false", from: CLOUDFLARE_EDGE, connecting_ips: [ VISITOR ])

    assert_equal CLOUDFLARE_EDGE, visits.sole["remote_ip"]
  end

  private
    def remote_ip(from:, connecting_ip:, worker: nil)
      RailsApp.visit(from: from, connecting_ip: connecting_ip, worker: worker)["remote_ip"]
    end

    def visit_booted_app(config, from:, connecting_ips:)
      stdout, stderr, status = run_app(config, <<~RUBY)
        puts JSON.generate(#{connecting_ips.inspect}.map { |ip| RailsApp.visit(from: #{from.inspect}, connecting_ip: ip) })
      RUBY

      assert status.success?, stderr
      JSON.parse(stdout)
    end

    def visit_app_with_initializer(source, from:, connecting_ips:)
      Dir.mktmpdir do |initializers|
        File.write(File.join(initializers, "cloudflare_visitor_ip.rb"), source)
        visit_booted_app(%(RailsApp.paths["config/initializers"] = #{initializers.inspect}), from: from, connecting_ips: connecting_ips)
      end
    end

    # An app boots once per process, so each configuration gets its own.
    def run_app(config, after_boot = "")
      Open3.capture3(RbConfig.ruby, "-Ilib", "-Itest", "-e", <<~RUBY)
        require "fixtures/rails_app"
        #{config}
        RailsApp.boot
        #{after_boot}
      RUBY
    end
end
