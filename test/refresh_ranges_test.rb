require "test_helper"
require "json"
require "tmpdir"
require "fileutils"
load File.expand_path("../script/refresh-ranges", __dir__)

class RefreshRangesTest < ActiveSupport::TestCase
  PUBLISHED = JSON.parse(File.read(File.expand_path("fixtures/cloudflare_ips.json", __dir__)))
  CHANGELOG = "# Changelog\n\n## 0.1.0 (2026-10-18)\n\nFirst release.\n"

  setup do
    @root = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@root, "data"))
    FileUtils.mkdir_p(File.join(@root, "lib/cloudflare_visitor_ip"))
    File.write(File.join(@root, "data/ips-v4.txt"), PUBLISHED["result"]["ipv4_cidrs"].join("\n") + "\n")
    File.write(File.join(@root, "data/ips-v6.txt"), PUBLISHED["result"]["ipv6_cidrs"].join("\n") + "\n")
    File.write(File.join(@root, "lib/cloudflare_visitor_ip/version.rb"), %(module CloudflareVisitorIp\n  VERSION = "0.1.0"\nend\n))
    File.write(File.join(@root, "CHANGELOG.md"), CHANGELOG)
    @refresh = RangesRefresh.new(root: @root, today: Date.new(2026, 10, 25))
  end

  teardown { FileUtils.remove_entry(@root) }

  test "ranges that match the data files change nothing" do
    assert_no_changes -> { snapshot } do
      assert_nil @refresh.apply(JSON.generate(PUBLISHED))
    end
  end

  test "the same ranges in another order change nothing" do
    assert_no_changes -> { snapshot } do
      assert_nil @refresh.apply(published { |result| result["ipv4_cidrs"].reverse! })
    end
  end

  test "changed ranges rewrite the data files, bump the patch version and add a CHANGELOG entry" do
    version = @refresh.apply(published do |result|
      result["ipv4_cidrs"].delete("131.0.72.0/22")
      result["ipv4_cidrs"] << "192.0.2.0/24"
    end)

    assert_equal "0.1.1", version
    assert_equal PUBLISHED["result"]["ipv4_cidrs"] - [ "131.0.72.0/22" ] + [ "192.0.2.0/24" ], read("data/ips-v4.txt").lines(chomp: true)
    assert_equal PUBLISHED["result"]["ipv6_cidrs"], read("data/ips-v6.txt").lines(chomp: true)
    assert_includes read("lib/cloudflare_visitor_ip/version.rb"), %(VERSION = "0.1.1")
    assert_equal <<~MD + CHANGELOG.delete_prefix("# Changelog\n\n"), read("CHANGELOG.md")
      # Changelog

      ## 0.1.1 (2026-10-25)

      Cloudflare changed its published IP ranges.

      - Adds `192.0.2.0/24`.
      - Removes `131.0.72.0/22`.

    MD
  end

  test "a family that keeps half its ranges is accepted" do
    assert_equal "0.1.1", @refresh.apply(published do |result|
      result["ipv4_cidrs"] = result["ipv4_cidrs"].first(8)
      result["ipv6_cidrs"] = result["ipv6_cidrs"].first(4)
    end)
  end

  test "a response that fails a check is refused and nothing is written" do
    refusals = {
      "not JSON" => "<html>Bad gateway</html>",
      "not an object" => "[]",
      "success false" => published { |result, json| json["success"] = false },
      "success missing" => published { |result, json| json.delete("success") },
      "result missing" => published { |result, json| json.delete("result") },
      "result not an object" => published { |result, json| json["result"] = [] },
      "IPv4 empty" => published { |result| result["ipv4_cidrs"] = [] },
      "IPv6 empty" => published { |result| result["ipv6_cidrs"] = [] },
      "IPv4 missing" => published { |result| result.delete("ipv4_cidrs") },
      "IPv6 not a list" => published { |result| result["ipv6_cidrs"] = "2400:cb00::/32" },
      "unparseable entry" => published { |result| result["ipv4_cidrs"] << "not-a-cidr" },
      "entry with no prefix" => published { |result| result["ipv4_cidrs"] << "192.0.2.0" },
      "prefix too long" => published { |result| result["ipv4_cidrs"] << "192.0.2.0/33" },
      "entry not a string" => published { |result| result["ipv4_cidrs"] << 42 },
      "IPv6 entry in the IPv4 list" => published { |result| result["ipv4_cidrs"] << "2001:db8::/32" },
      "IPv4 entry in the IPv6 list" => published { |result| result["ipv6_cidrs"] << "192.0.2.0/24" },
      "host bits set" => published { |result| result["ipv4_cidrs"] << "192.0.2.1/24" },
      "IPv6 host bits set" => published { |result| result["ipv6_cidrs"] << "2001:db8::1/32" },
      "IPv4 shrinks below half" => published { |result| result["ipv4_cidrs"] = result["ipv4_cidrs"].first(7) },
      "IPv6 shrinks below half" => published { |result| result["ipv6_cidrs"] = result["ipv6_cidrs"].first(3) }
    }

    refusals.each do |reason, body|
      assert_no_changes -> { snapshot }, reason do
        assert_raises(RangesRefresh::Refused, reason) { @refresh.apply(body) }
      end
    end
  end

  test "an empty family is refused even when its data file is empty" do
    File.write(File.join(@root, "data/ips-v6.txt"), "")

    assert_no_changes -> { snapshot } do
      assert_raises(RangesRefresh::Refused) { @refresh.apply(published { |result| result["ipv6_cidrs"] = [] }) }
    end
  end

  private
    def published
      json = JSON.parse(JSON.generate(PUBLISHED))
      yield json["result"], json
      JSON.generate(json)
    end

    def read(path) = File.read(File.join(@root, path))

    def snapshot
      Dir.glob("**/*", base: @root).sort.to_h { |path| [ path, File.file?(File.join(@root, path)) && read(path) ] }
    end
end
