module Aicoo
  module Serp
    class SearchResult
      def initialize(payload)
        @payload = payload.deep_stringify_keys
      end

      def to_h
        @payload
      end

      def as_json(*)
        to_h
      end

      def provider
        @payload["provider"]
      end

      def type
        @payload["type"]
      end

      def organic_results
        @payload.fetch("organic_results", [])
      end
    end
  end
end
