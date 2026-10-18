require "test_helper"

class CloudflareVisitorIpTest < ActiveSupport::TestCase
  test "ranges are the CIDRs in the data files, IPv4 first" do
    published = File.readlines(data_file("ips-v4.txt"), chomp: true) + File.readlines(data_file("ips-v6.txt"), chomp: true)

    assert_equal published, CloudflareVisitorIp.ranges.map { |range| "#{range}/#{range.prefix}" }
    assert_predicate CloudflareVisitorIp.ranges, :frozen?
  end

  test "addresses inside Cloudflare's ranges are included" do
    [ "173.245.48.1", "104.23.255.255", "172.71.10.20", "2606:4700::10", "2a06:98c0:3600::103" ].each do |address|
      assert CloudflareVisitorIp.include?(address), address
    end
  end

  test "an IPv4-mapped IPv6 address inside Cloudflare's IPv4 ranges is included" do
    assert CloudflareVisitorIp.include?("::ffff:172.71.10.20")
  end

  test "addresses outside Cloudflare's ranges are not included" do
    [ "104.15.255.255", "172.72.0.0", "172.18.0.2", "198.51.100.20", "2001:db8::7", "2606:4701::1" ].each do |address|
      assert_not CloudflareVisitorIp.include?(address), address
    end
  end

  test "input that is not an address is not included" do
    [ nil, "", "unknown", "104.16.0.1, 104.16.0.2", "999.16.0.1" ].each do |address|
      assert_equal false, CloudflareVisitorIp.include?(address), address.inspect
    end
  end

  test "ipv6_prefix is 64 unless set" do
    assert_equal 64, CloudflareVisitorIp.ipv6_prefix
  end

  test "an ipv6_prefix outside 1 to 128 is refused and the prefix keeps its value" do
    [ 0, 129, "56", 56.0, nil ].each do |prefix|
      error = assert_raises(ArgumentError, prefix.inspect) { CloudflareVisitorIp.ipv6_prefix = prefix }
      assert_includes error.message, "CloudflareVisitorIp.ipv6_prefix"
    end
    assert_equal 64, CloudflareVisitorIp.ipv6_prefix
  end

  private
    def data_file(name) = File.expand_path("../data/#{name}", __dir__)
end
