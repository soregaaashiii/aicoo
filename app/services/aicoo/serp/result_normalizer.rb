module Aicoo
  module Serp
    class ResultNormalizer
      def self.call(...)
        new(...).call
      end

      def initialize(provider:, type:, query:, location:, language:, raw_response:)
        @provider = provider.to_s
        @type = type.to_s
        @query = query.to_s
        @location = location.to_s
        @language = language.to_s
        @raw_response = raw_response || {}
      end

      def call
        SearchResult.new(
          provider:,
          type:,
          query:,
          location:,
          language:,
          fetched_at: Time.current.iso8601,
          organic_results: organic_results,
          people_also_ask: people_also_ask,
          related_searches: related_searches,
          ai_overview: ai_overview,
          raw_response:
        )
      end

      private

      attr_reader :provider, :type, :query, :location, :language, :raw_response

      def organic_results
        Array(raw_response["organic"]).each_with_index.map do |row, index|
          {
            position: integer_value(row["position"]) || index + 1,
            title: row["title"].to_s,
            url: row["link"].presence || row["url"].to_s,
            displayed_url: row["displayedLink"].presence || row["displayed_url"].to_s,
            snippet: row["snippet"].to_s,
            source: row["source"].presence || provider,
            raw: row
          }
        end
      end

      def people_also_ask
        Array(raw_response["peopleAlsoAsk"]).map do |row|
          {
            question: row["question"].to_s,
            snippet: row["snippet"].to_s,
            title: row["title"].to_s,
            url: row["link"].to_s,
            raw: row
          }
        end
      end

      def related_searches
        Array(raw_response["relatedSearches"]).map do |row|
          row.is_a?(Hash) ? row["query"].to_s : row.to_s
        end.compact_blank
      end

      def ai_overview
        raw_response["aiOverview"] || raw_response["ai_overview"]
      end

      def integer_value(value)
        Integer(value)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
