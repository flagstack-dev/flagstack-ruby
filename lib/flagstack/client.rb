require "net/http"
require "json"

module Flagstack
  class Client
    def initialize(config)
      @config = config
      @etag = nil
    end

    def sync
      uri = URI("#{@config.url}/api/v1/sync")

      response = request(:get, uri) do |req|
        req["If-None-Match"] = @etag if @etag
      end

      case response.code.to_i
      when 200
        @etag = response["ETag"]
        @config.log("Sync successful (ETag: #{@etag})", level: :debug)
        JSON.parse(response.body)
      when 304
        @config.log("Sync not modified (304)", level: :debug)
        nil # Cache is current
      when 401
        raise APIError, "Invalid API token"
      when 429
        @config.log("Rate limited, backing off", level: :warn)
        nil
      else
        raise APIError, "API error: #{response.code} #{response.body}"
      end
    rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
      @config.log("Connection failed: #{e.message}", level: :error)
      nil
    end

    def check(feature_key, actor_id: nil)
      uri = URI("#{@config.url}/api/v1/features/#{feature_key}/check")
      uri.query = URI.encode_www_form(actor_id: actor_id) if actor_id

      response = request(:get, uri)
      data = JSON.parse(response.body)
      data["enabled"]
    end

    # Check if the Flagstack server is reachable and the token is valid
    # Returns a hash with :ok (boolean) and :message (string)
    def health_check
      uri = URI("#{@config.url}/api/v1/sync")

      response = request(:get, uri)

      case response.code.to_i
      when 200, 304
        { ok: true, message: "Connected to Flagstack" }
      when 401
        { ok: false, message: "Invalid API token" }
      when 429
        { ok: true, message: "Connected (rate limited)" }
      else
        { ok: false, message: "Unexpected response: #{response.code}" }
      end
    rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
      { ok: false, message: "Connection timeout: #{e.message}" }
    rescue Errno::ECONNREFUSED => e
      { ok: false, message: "Connection refused: #{e.message}" }
    rescue => e
      { ok: false, message: "Connection failed: #{e.message}" }
    end

    def post_telemetry(compressed_body)
      uri = URI("#{@config.url}/api/v1/telemetry")

      response = request(:post, uri) do |req|
        req["Content-Type"] = "application/json"
        req["Content-Encoding"] = "gzip"
        req.body = compressed_body
      end

      case response.code.to_i
      when 200..299
        @config.log("Telemetry submitted successfully", level: :debug)
        response
      when 429
        @config.log("Telemetry rate limited", level: :warn)
        nil
      else
        @config.log("Telemetry failed: #{response.code}", level: :error)
        nil
      end
    rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
      @config.log("Telemetry connection failed: #{e.message}", level: :error)
      nil
    end

    private

    def request(method, uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = @config.read_timeout
      http.open_timeout = @config.open_timeout
      http.write_timeout = @config.write_timeout if http.respond_to?(:write_timeout=)

      # Debug output
      http.set_debug_output(@config.debug_output) if @config.debug_output

      request = case method
      when :get then Net::HTTP::Get.new(uri)
      when :post then Net::HTTP::Post.new(uri)
      else raise ArgumentError, "Unknown method: #{method}"
      end

      request["Authorization"] = "Bearer #{@config.token}"
      request["User-Agent"] = "flagstack-ruby/#{VERSION}"
      request["Accept"] = "application/json"

      yield request if block_given?

      @config.instrument("http_request", method: method, uri: uri.to_s) do
        http.request(request)
      end
    end
  end
end
