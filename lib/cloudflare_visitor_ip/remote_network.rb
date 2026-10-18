module CloudflareVisitorIp
  module RemoteNetwork
    # An IPv6 visitor usually holds a whole /64 or more, so per-IP limits count the network.
    def remote_network
      address = IPAddr.new(remote_ip)
      prefix = address.ipv6? ? CloudflareVisitorIp.ipv6_prefix : 32
      "#{address.mask(prefix)}/#{prefix}"
    end
  end
end
