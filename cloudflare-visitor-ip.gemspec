require_relative "lib/cloudflare_visitor_ip/version"

Gem::Specification.new do |spec|
  spec.name = "cloudflare-visitor-ip"
  spec.version = CloudflareVisitorIp::VERSION
  spec.authors = [ "Dave Bradford" ]
  spec.email = [ "dbradford@hey.com" ]
  spec.summary = "Sets request.remote_ip to the visitor behind a Cloudflare edge, and ships Cloudflare's IP ranges."
  spec.homepage = "https://github.com/zerobearing2/cloudflare-visitor-ip"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "data/*", "exe/*", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.bindir = "exe"
  spec.executables = [ "cloudflare-ips" ]

  spec.add_dependency "actionpack", ">= 7.2", "< 9"
  spec.add_dependency "railties", ">= 7.2", "< 9"
end
