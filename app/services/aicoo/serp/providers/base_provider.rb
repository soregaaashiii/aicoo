require "json"
require "net/http"

module Aicoo
  module Serp
    module Providers
      class BaseProvider
        DEFAULT_TIMEOUT_SECONDS = 20

        def call(type:, query:, location:, language:, limit:)
          raise UnsupportedSearchTypeError, "#{provider_name} は #{type} に未対応です"
        end

        private

        def provider_name
          self.class.name.demodulize.underscore.sub(/_provider\z/, "")
        end

        def require_api_key!(value, label)
          raise MissingApiKeyError, "#{label} が未設定です" if value.blank?
        end

        def post_json(uri, body:, headers: {}, timeout: DEFAULT_TIMEOUT_SECONDS)
          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          headers.each { |key, value| request[key] = value }
          request.body = JSON.generate(body)

          response = Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: timeout,
            read_timeout: timeout
          ) { |http| http.request(request) }
          parse_response(response)
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          raise TimeoutError, "SERP APIがタイムアウトしました: #{e.message}"
        rescue JSON::ParserError => e
          raise ParseError, "SERP APIレスポンスのJSON解析に失敗しました: #{e.message}"
        end

        def parse_response(response)
          body = response.body.to_s
          raise RateLimitError, "SERP APIのRate Limitに到達しました: #{body}" if response.code.to_i == 429
          raise HttpError, "SERP API HTTP失敗: #{response.code} #{body}" unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(body)
        end
      end
    end
  end
end
