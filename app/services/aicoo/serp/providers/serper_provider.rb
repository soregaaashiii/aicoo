module Aicoo
  module Serp
    module Providers
      class SerperProvider < BaseProvider
        ENDPOINT = "https://google.serper.dev/search"

        def call(type:, query:, location:, language:, limit:)
          raise UnsupportedSearchTypeError, "Serperは #{type} に未対応です" unless type.to_sym == :google_search

          api_key = resolved_api_key
          require_api_key!(api_key, "SERPER_API_KEY")

          raw_response = post_json(
            URI(ENDPOINT),
            body: {
              q: query.to_s,
              location: location.to_s,
              hl: language.to_s,
              num: limit.to_i.clamp(1, 100)
            },
            headers: { "X-API-KEY" => api_key }
          )

          ResultNormalizer.call(
            provider: "serper",
            type:,
            query:,
            location:,
            language:,
            raw_response:
          )
        end

        private

        def resolved_api_key
          ENV["SERPER_API_KEY"].presence ||
            DataSourceCostProfile.find_by(source_key: "serp")&.api_key
        end
      end
    end
  end
end
