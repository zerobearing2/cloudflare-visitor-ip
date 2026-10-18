# Changelog

## 0.1.0 (2026-10-18)

First release, extracted from feedback-app.

- Ships Cloudflare's IP ranges in `data/ips-v4.txt` and `data/ips-v6.txt`. `CloudflareVisitorIp.ranges` reads them, and `cloudflare-ips` prints them for firewall scripts.
- Sets `request.remote_ip` to `CF-Connecting-IP` when the peer is a Cloudflare edge and the header names one address. The middleware runs before `Rails::Rack::Logger`, so the request log names the visitor. `config.cloudflare_visitor_ip.middleware = false` turns it off.
- Adds `request.remote_network` for `rate_limit` keys, in CIDR notation: the IPv4 address as a /32, or the IPv6 network at `config.cloudflare_visitor_ip.ipv6_prefix`, which defaults to 64.
