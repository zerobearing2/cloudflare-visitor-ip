# cloudflare-visitor-ip

Behind Cloudflare, `request.remote_ip` in a Rails app is the Cloudflare edge that connected to your origin, not the visitor. Every visitor behind one edge then shares one address in your logs and one count in every per-IP `rate_limit`. This gem sets `request.remote_ip` to the visitor's address from the `CF-Connecting-IP` header, but only when the request came from an address in Cloudflare's published ranges.

The gem also ships those ranges as the one list your app and your firewall scripts read, adds `request.remote_network` for rate-limit keys, and keeps the list current through a weekly pull request.

Requires Ruby 3.2 or later and Rails 7.2, 8.0, or 8.1. CI runs the suite on Ruby 4.0 against each of those Rails versions.

## Install the gem

The gem is not on RubyGems. Install it from GitHub, pinned to a release tag:

```ruby
# Gemfile
gem "cloudflare-visitor-ip", github: "zerobearing2/cloudflare-visitor-ip", tag: "v0.1.0"
```

Run `bundle install`. Bundler requires the gem for you, and the gem's Railtie adds the middleware, so there is nothing else to configure. To upgrade, change the tag and run `bundle update cloudflare-visitor-ip`. Dependabot also opens a pull request when a new tag appears.

## How the gem finds the visitor

`CloudflareVisitorIp::Middleware` runs after `ActionDispatch::RemoteIp` and before `Rails::Rack::Logger`. It reads the address that `RemoteIp` found, called the peer below, and sets `request.remote_ip` to the `CF-Connecting-IP` header when all of these are true:

- The peer is inside one of Cloudflare's ranges in `data/ips-v4.txt` or `data/ips-v6.txt`.
- The request has no `CF-Worker` header.
- The header names exactly one address. A /32 or /128 counts as one address. An IPv4-mapped IPv6 address, such as `::ffff:203.0.113.7`, becomes its IPv4 address.

In every other case `request.remote_ip` stays the peer. A request from outside Cloudflare can send any `CF-Connecting-IP` it likes, and the gem ignores it. A Cloudflare edge overwrites the header with the address that connected to it, so a visitor cannot choose the value that arrives from an edge.

A Cloudflare Worker's `fetch()` is the exception. When it fetches a hostname that is not proxied through Cloudflare, the Worker writes `CF-Connecting-IP` itself. Cloudflare adds a `CF-Worker` header to every Worker `fetch()`, so the gem ignores `CF-Connecting-IP` on any request that has one. [Worker fetches](#worker-fetches-are-counted-by-the-edge-address) explains the attack and what it costs you.

`RemoteIp` must already resolve the peer to the Cloudflare edge. With kamal-proxy and Thruster in front of Puma, the defaults do that. kamal-proxy terminates TLS and writes the edge into `X-Forwarded-For`, and `RemoteIp` skips the private addresses of kamal-proxy and Thruster. Do not add Cloudflare's ranges to `config.action_dispatch.trusted_proxies`. The next section explains why.

To turn the middleware off, set this in `config/application.rb` or in a file in `config/initializers`:

```ruby
config.cloudflare_visitor_ip.middleware = false
```

### Your request log now holds visitor addresses

The middleware runs before the request logger, so each `Started GET "/" for 203.0.113.7` line names the visitor, not the edge. An audit needs that address. It also means your logs store personal data. Disclosing that in your privacy policy, and setting a log retention period, is your app's job.

## Why not trusted_proxies

The usual Rails answer is to add Cloudflare's ranges to `config.action_dispatch.trusted_proxies` and let `RemoteIp` read the visitor from `X-Forwarded-For`. Behind kamal-proxy, that also needs `forward_headers: true`, so kamal-proxy keeps the header Cloudflare sent. The design can be spoofed.

A Cloudflare Worker on any Cloudflare account sends its outbound requests from `2a06:98c0:3600::103`, which is inside Cloudflare's published `2a06:98c0::/29`. The Worker writes whatever `X-Forwarded-For` it likes. Because the Worker's address is a trusted proxy, `RemoteIp` skips it and believes the forged address behind it. Anyone with a free Cloudflare account can then pick the address your rate limits count.

`CF-Connecting-IP` has that hole in one case only. When a Worker fetches a hostname that is not proxied through Cloudflare, the Worker writes the header, and the gem closes that case by checking `CF-Worker`. When a Worker in another zone fetches your proxied hostname, Cloudflare sets the header to `2a06:98c0:3600::103`, and the Worker cannot change it. The kamal-proxy setup above also drops any `X-Forwarded-For` the client sent, so the design needs no `forward_headers` change in `deploy.yml`.

## Rate-limit by the visitor's network

`request.remote_ip` stays the visitor's exact address. Use it for logs, audit records, and anything else that records who made a request.

`request.remote_network` is for rate-limit and abuse keys only. It returns the visitor's network in CIDR notation:

| `request.remote_ip` | `request.remote_network` |
|---|---|
| `203.0.113.7` | `203.0.113.7/32` |
| `::ffff:203.0.113.7` | `203.0.113.7/32` |
| `2001:db8:1:2::7` | `2001:db8:1:2::/64` |
| `2001:db8:1:2:ffff::1` | `2001:db8:1:2::/64` |

An ISP usually gives each IPv6 customer at least a /64, which holds 2^64 addresses. A per-address limit lets that customer rotate through addresses forever. Counting the /64 counts the customer.

Rails' `rate_limit` keys on `request.remote_ip` unless you pass `by:`. Pass `remote_network` explicitly:

```ruby
class SessionsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :create, by: -> { request.remote_network }
end
```

### Choose the IPv6 prefix

Some ISPs give each customer a /56 or a /48, which holds 256 or 65,536 /64s. One customer can then spread requests over many /64 networks. To count a wider network, set the prefix in `config/application.rb` or in a file in `config/initializers`:

```ruby
config.cloudflare_visitor_ip.ipv6_prefix = 56
```

`request.remote_network` then returns, for example, `2001:db8:1::/56`. A wider prefix also puts more neighbors into one count. A /48 can hold every customer of a small ISP or a whole office, so they share one limit. The default is 64. IPv4 always uses /32.

The value must be an Integer from 1 to 128. Any other value raises `ArgumentError` when the app boots. Outside Rails, read and set the same value with `CloudflareVisitorIp.ipv6_prefix`.

### Keep Pseudo IPv4 off Overwrite Headers

Cloudflare's **Pseudo IPv4** setting, on the zone's **Network** page, has three values: **Off**, **Add Header**, and **Overwrite Headers**. Cloudflare's [Pseudo IPv4](https://developers.cloudflare.com/network/pseudo-ipv4/) page says that with **Overwrite Headers**, Cloudflare "overwrites the existing `Cf-Connecting-IP` and `X-Forwarded-For` headers with a pseudo IPv4 address while preserving the real IPv6 address in `CF-Connecting-IPv6` header." The pseudo address is a Class E address that Cloudflare hashes from the visitor's IPv6 address. `request.remote_ip` is then that pseudo address, and `request.remote_network` is its /32. Each IPv6 address hashes to its own pseudo address, so a visitor who rotates through a /64 gets a new rate-limit key with each address.

Keep the setting at **Off**, the default, or **Add Header**. With **Add Header**, Cloudflare adds a `Cf-Pseudo-IPv4` header, and the page describes no change to `CF-Connecting-IP`.

The gem does not read `CF-Connecting-IPv6`. Cloudflare does not document whether an edge removes a `CF-Connecting-IPv6` header that a visitor sends when the setting is not **Overwrite Headers**. If it does not, a visitor could choose that value.

## Restrict your firewall to Cloudflare

The gem's ranges are the list your firewall should admit on ports 80 and 443. `cloudflare-ips` prints them one CIDR per line and loads nothing from Rails:

```sh
bundle exec cloudflare-ips        # every range, IPv4 first
bundle exec cloudflare-ips --v4   # IPv4 only
bundle exec cloudflare-ips --v6   # IPv6 only
```

Any other argument prints usage to stderr and exits with status 2. In a firewall script, read the ranges from the app's bundle instead of fetching them from Cloudflare:

```bash
CF_V4=$(bundle exec cloudflare-ips --v4)
CF_V6=$(bundle exec cloudflare-ips --v6)
```

The firewall then admits the same ranges the app believes. From Ruby, `CloudflareVisitorIp.v4_ranges`, `.v6_ranges`, and `.ranges` return frozen arrays of `IPAddr`, and `CloudflareVisitorIp.include?(address)` returns `true` for an address inside them and `false` for anything else, including input that is not an address. `require "cloudflare_visitor_ip"` loads only that part, without Rails.

### Re-sync the firewall on each deploy

A new gem tag reaches production when the app deploys. To update the firewall at the same moment, run your firewall script from Kamal's `post-deploy` hook. Kamal runs hooks on the machine you deploy from, so the hook reads the ranges from the same `Gemfile.lock` as the deploy:

```bash
#!/usr/bin/env bash
# .kamal/hooks/post-deploy
set -euo pipefail

bin/cloudflare-firewall
```

## Keep the ranges current

The **Refresh ranges** workflow runs `script/refresh-ranges` every Monday and on demand. The script fetches `https://api.cloudflare.com/client/v4/ips` and compares it with `data/`. When the ranges differ, it rewrites the data files, bumps the patch version in `lib/cloudflare_visitor_ip/version.rb`, and adds a CHANGELOG entry. The workflow then opens a pull request from the `refresh-ranges` branch.

Firewalls read these files, so the script refuses to write anything, and exits with status 1, when any of these is true:

- The response is not JSON, or `success` is not `true`.
- Either family is missing or empty.
- Any entry is not a CIDR string, is the other family, or has host bits set, such as `192.0.2.1/24`.
- Any IPv4 entry is wider than /12, or any IPv6 entry is wider than /20.
- Any entry overlaps a range that is not public: `0.0.0.0/8`, a private, loopback, or link-local range of either family, the IPv6 unspecified address `::`, or the IPv4-mapped block `::ffff:0:0/96`.
- Either family has fewer than half the ranges in its data file.

To run it by hand, run `script/refresh-ranges` from the repository root. It needs only Ruby's standard library.

### Let the refresh pull request run CI

A pull request opened with the workflow's `GITHUB_TOKEN` does not trigger other workflows, so CI does not run on it. Do one of these:

- Add a repository secret named `RANGES_PR_TOKEN` that holds a fine-grained personal access token or a GitHub App token with **Contents** and **Pull requests** write access to this repository. The workflow uses it when it exists.
- Close and reopen the pull request, or push a commit to its branch. Either one triggers CI as you.

Without `RANGES_PR_TOKEN`, the workflow needs **Allow GitHub Actions to create and approve pull requests** turned on in the repository's **Settings > Actions > General**.

### Release a new version

The **Release** workflow runs after CI passes on a push to `main`. If the tag `v<VERSION>` does not exist yet, it tags that commit and pushes the tag. Merging a refresh pull request therefore releases a new version, and Dependabot in each app opens a pull request for the new tag. A commit with a red CI run is never tagged.

Until an app deploys the new tag, it keeps the old ranges. A visitor who arrives through a range Cloudflare added is known by the edge address, and a firewall that reads the gem's ranges drops that traffic. The weekly refresh keeps that window short. It does not close it.

## What the gem does not protect against

- **Other Cloudflare zones.** The middleware believes any Cloudflare edge, not only your zone's edges. A Cloudflare Enterprise customer can point a zone at your origin, override Host and SNI, and choose the `CF-Connecting-IP` your app sees. A shared-secret header set by a Cloudflare Transform Rule, checked by the app, would close this. The gem does not do that.
- **Hostnames your origin does not serve.** A Worker can reach your origin under a hostname you do not control, as the next section describes. The gem's `CF-Worker` check stops that Worker from choosing your app's `remote_ip`, but your app still answers the request. Make the origin refuse any Host and TLS SNI it does not serve. kamal-proxy does that when `proxy.hosts` lists your hostnames and `proxy.ssl` is `true`. [Authenticated Origin Pulls](https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/) with your own certificate is stronger, because the origin then accepts TLS only from your zone.

### Worker fetches are counted by the edge address

Cloudflare's [HTTP request headers](https://developers.cloudflare.com/fundamentals/reference/http-headers/) page says that on a Worker subrequest to a hostname outside Cloudflare, "the Worker script controls the client IP headers". That gives an attacker this path to your app:

1. The attacker points a DNS-only hostname they own at your origin's IP address.
2. A Worker on the attacker's free Cloudflare account fetches that hostname and sets `CF-Connecting-IP` to any address.
3. The request leaves Cloudflare from an address inside Cloudflare's ranges, so the peer check passes.

The same page says `CF-Worker` "is added to all Worker subrequests sent via `fetch()`" and names the zone that owns the Worker. The middleware therefore keeps the edge address as `request.remote_ip` whenever `CF-Worker` is present. That has two costs:

- Requests from your own Workers are also counted by the edge address, not by the visitor the Worker acts for. All Worker traffic that reaches your origin through one edge address shares one rate-limit count. That includes Workers in other zones, whose requests through your proxied hostname carry `CF-Connecting-IP: 2a06:98c0:3600::103`.
- Cloudflare does not document whether it removes a `CF-Worker` header that a visitor sends. If it does not, a visitor can add one and be counted by the edge address instead of their own.

## Develop the gem

Run the suite against the latest supported Rails with `bundle exec rake`. Lint with `bundle exec rubocop`. To run against a specific Rails version, pick its gemfile:

```sh
BUNDLE_GEMFILE=gemfiles/rails_7_2.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_7_2.gemfile bundle exec rake
```

The tests never call Cloudflare. `test/fixtures/cloudflare_ips.json` is a saved API response.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
