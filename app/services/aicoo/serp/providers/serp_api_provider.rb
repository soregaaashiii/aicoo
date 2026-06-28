module Aicoo
  module Serp
    module Providers
      class SerpApiProvider < BaseProvider
        def call(type:, query:, location:, language:, limit:)
          raise UnsupportedSearchTypeError, "SerpAPI Providerは未実装です"
        end
      end
    end
  end
end
