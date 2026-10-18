require "test_helper"
require "open3"

class CloudflareIpsExeTest < ActiveSupport::TestCase
  EXE = File.expand_path("../exe/cloudflare-ips", __dir__)
  V4 = File.read(File.expand_path("../data/ips-v4.txt", __dir__))
  V6 = File.read(File.expand_path("../data/ips-v6.txt", __dir__))

  test "with no flag it prints every range, IPv4 first" do
    assert_equal [ V4 + V6, "", 0 ], cloudflare_ips
  end

  test "--v4 prints the IPv4 ranges" do
    assert_equal [ V4, "", 0 ], cloudflare_ips("--v4")
  end

  test "--v6 prints the IPv6 ranges" do
    assert_equal [ V6, "", 0 ], cloudflare_ips("--v6")
  end

  test "an unknown flag prints usage to stderr and exits 2" do
    [ [ "--v5" ], [ "--v4", "--v6" ], [ "v4" ] ].each do |args|
      stdout, stderr, status = cloudflare_ips(*args)

      assert_equal [ "", 2 ], [ stdout, status ], args.inspect
      assert_includes stderr, "Usage: cloudflare-ips [--v4|--v6]"
    end
  end

  private
    def cloudflare_ips(*args)
      stdout, stderr, status = Open3.capture3({ "RUBYOPT" => nil }, RbConfig.ruby, "--disable-gems", EXE, *args)
      [ stdout, stderr, status.exitstatus ]
    end
end
