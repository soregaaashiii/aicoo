require "ipaddr"
require "net/http"
require "uri"

module Aicoo
  class PublicHttpFetcher
    MAX_BYTES = 500_000
    MAX_REDIRECTS = 2
    BLOCKED_NETWORKS = %w[
      0.0.0.0/8
      10.0.0.0/8
      100.64.0.0/10
      127.0.0.0/8
      169.254.0.0/16
      172.16.0.0/12
      192.0.0.0/24
      192.168.0.0/16
      198.18.0.0/15
      224.0.0.0/4
      ::/128
      ::1/128
      fc00::/7
      fe80::/10
      ff00::/8
    ].map { |cidr| IPAddr.new(cidr) }.freeze

    Response = Data.define(:body, :content_type, :status, :url)

    class Error < StandardError; end

    def initialize(open_timeout: 4, read_timeout: 8)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def get(url, headers: {}, redirects_remaining: MAX_REDIRECTS)
      uri = validated_uri(url)
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "AICOO-BusinessRegistration/2.0"
      headers.each { |key, value| request[key] = value if value.present? }

      response = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: @open_timeout,
        read_timeout: @read_timeout
      ) { |http| http.request(request) }

      if response.is_a?(Net::HTTPRedirection)
        raise Error, "redirect limit exceeded" unless redirects_remaining.positive?

        redirect_url = URI.join(uri.to_s, response["location"].to_s).to_s
        return get(redirect_url, headers:, redirects_remaining: redirects_remaining - 1)
      end

      raise Error, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      Response.new(
        body: response.body.to_s.byteslice(0, MAX_BYTES),
        content_type: response["content-type"].to_s,
        status: response.code.to_i,
        url: uri.to_s
      )
    rescue SocketError, SystemCallError, Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
      raise Error, "fetch failed: #{e.class}: #{e.message}"
    end

    private

    attr_reader :open_timeout, :read_timeout

    def validated_uri(value)
      uri = URI.parse(value.to_s)
      unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.blank?
        raise Error, "public http(s) URL is required"
      end
      raise Error, "local hosts are not allowed" if local_hostname?(uri.host)

      addresses = Addrinfo.getaddrinfo(uri.host, nil).filter_map do |address|
        IPAddr.new(address.ip_address)
      rescue IPAddr::InvalidAddressError
        nil
      end
      raise Error, "host could not be resolved" if addresses.empty?
      raise Error, "private network hosts are not allowed" if addresses.any? { |address| blocked_address?(address) }

      uri
    rescue URI::InvalidURIError => e
      raise Error, "invalid URL: #{e.message}"
    end

    def local_hostname?(host)
      normalized = host.to_s.downcase.delete_suffix(".")
      normalized == "localhost" || normalized.end_with?(".localhost", ".local", ".internal")
    end

    def blocked_address?(address)
      BLOCKED_NETWORKS.any? { |network| network.include?(address) }
    end
  end
end
