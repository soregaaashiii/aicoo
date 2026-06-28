module Aicoo
  module Serp
    class ProviderRegistry
      PROVIDERS = {
        serper: "Aicoo::Serp::Providers::SerperProvider",
        data_for_seo: "Aicoo::Serp::Providers::DataForSeoProvider",
        serp_api: "Aicoo::Serp::Providers::SerpApiProvider"
      }.freeze

      def self.fetch(provider)
        key = provider.to_s.presence || ENV["AICOO_SERP_PROVIDER"].presence || "serper"
        klass_name = PROVIDERS[key.to_sym]
        raise UnsupportedProviderError, "未対応のSERP Providerです: #{key}" if klass_name.blank?

        klass_name.constantize
      end

      def self.provider_keys
        PROVIDERS.keys
      end
    end
  end
end
