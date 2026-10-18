module CloudflareVisitorIp
  # Behind Cloudflare, remote_ip is the edge that connected to the origin. The
  # edge sets CF-Connecting-IP to the visitor and overwrites any value the client
  # sent. From any other peer the header is the client's word.
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      request = ActionDispatch::Request.new(env)
      if visitor = visitor_behind_cloudflare(request)
        request.remote_ip = visitor
      end
      @app.call(env)
    end

    private
      def visitor_behind_cloudflare(request)
        if CloudflareVisitorIp.include?(request.remote_ip)
          single_address(request.headers["CF-Connecting-IP"])
        end
      end

      def single_address(value)
        address = IPAddr.new(value.to_s)
        address.to_s if address.prefix == (address.ipv4? ? 32 : 128)
      rescue IPAddr::Error
        nil
      end
  end
end
