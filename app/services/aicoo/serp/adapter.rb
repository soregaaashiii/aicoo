module Aicoo
  module Serp
    class Adapter
      TYPES = %i[
        google_search
        google_maps
        news
        shopping
        ai_overview
        images
        videos
      ].freeze

      # Future persistence design:
      # - SerpFetchRun: provider, search_type, query, location, language, status,
      #   started_at, finished_at, duration_seconds, error_message, raw_response.
      # - SerpResult: serp_fetch_run_id, position, title, url, displayed_url,
      #   snippet, result_type, metadata.
      # Keeping this layer DB-free for now lets AICOO switch providers safely
      # before coupling SERP fetches to storage.
      def self.call(...)
        new.call(...)
      end

      def call(provider: nil, type: :google_search, query:, location: "Japan", language: "ja", limit: 10)
        search_type = type.to_sym
        raise UnsupportedSearchTypeError, "未対応の検索タイプです: #{type}" unless TYPES.include?(search_type)

        provider_class = ProviderRegistry.fetch(provider || ENV["AICOO_SERP_PROVIDER"].presence || :serper)
        provider_class.new.call(
          type: search_type,
          query:,
          location:,
          language:,
          limit:
        )
      end
    end
  end
end
