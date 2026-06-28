module Aicoo
  module Serp
    module Providers
      class DataForSeoProvider < BaseProvider
        def call(type:, query:, location:, language:, limit:)
          raise UnsupportedSearchTypeError, "DataForSEO Providerは未実装です"
        end
      end
    end
  end
end
