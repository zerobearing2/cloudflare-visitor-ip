require "ipaddr"
require_relative "cloudflare_visitor_ip/version"

module CloudflareVisitorIp
  def self.read_ranges(name)
    File.readlines(File.expand_path("../data/#{name}", __dir__), chomp: true).map { |cidr| IPAddr.new(cidr).freeze }.freeze
  end
  private_class_method :read_ranges

  V4_RANGES = read_ranges("ips-v4.txt")
  V6_RANGES = read_ranges("ips-v6.txt")
  RANGES = (V4_RANGES + V6_RANGES).freeze

  def self.ranges = RANGES
  def self.v4_ranges = V4_RANGES
  def self.v6_ranges = V6_RANGES

  def self.include?(address)
    ip = IPAddr.new(address.to_s)
    RANGES.any? { |range| range.include?(ip) }
  rescue IPAddr::Error
    false
  end
end
