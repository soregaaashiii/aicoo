module Aicoo
  class RequestQueryContext < ActiveSupport::CurrentAttributes
    attribute :active, :records

    class << self
      def within
        self.active = true
        self.records = {}
        yield
      ensure
        reset
      end

      def data_source_cost_profile(source_key)
        return yield unless active?

        data_source_cost_profiles.fetch(source_key.to_s) { yield }
      end

      def proxy_score_weight(business)
        return yield unless active?

        proxy_score_weights.fetch(business&.id, proxy_score_weights[nil]) || yield
      end

      def business_data_source_setting(business, source_key)
        return yield unless active?

        business_data_source_settings[[ business&.id, source_key.to_s ]]
      end

      def analytics_source_settings
        return yield unless active?

        records[:analytics_source_settings] ||= AnalyticsSourceSetting
          .includes(:aicoo_analytics_site, :google_credential)
          .to_a
      end

      def analytics_site(business)
        return yield unless active?

        analytics_sites(business).first
      end

      def analytics_sites(business)
        return yield unless active?

        analytics_sites_by_business_id.fetch(business&.id, [])
      end

      def google_credential(id)
        return yield unless active?

        google_credentials_by_id[id.to_i]
      end

      def default_google_credential
        return yield unless active?

        records[:default_google_credential] ||= google_credentials
          .select(&:enabled?)
          .max_by(&:created_at)
      end

      def analytics_fetch_runs
        return yield unless active?

        records[:analytics_fetch_runs] ||= AnalyticsFetchRun.recent.to_a
      end

      def serp_query_count(business)
        return yield unless active?

        serp_query_counts.fetch(business&.id, 0)
      end

      def business_serp_keyword_count(business)
        return yield unless active?

        business_serp_keyword_counts.fetch(business&.id, 0)
      end

      private

      def active?
        active == true
      end

      def data_source_cost_profiles
        records[:data_source_cost_profiles] ||= DataSourceCostProfile.all.index_by(&:source_key)
      end

      def proxy_score_weights
        records[:proxy_score_weights] ||= ProxyScoreWeight
          .order(updated_at: :desc)
          .to_a
          .group_by(&:business_id)
          .transform_values(&:first)
      end

      def business_data_source_settings
        records[:business_data_source_settings] ||= BusinessDataSourceSetting.all.index_by do |setting|
          [ setting.business_id, setting.source_key ]
        end
      end

      def analytics_sites_by_business_id
        records[:analytics_sites_by_business_id] ||= AicooAnalyticsSite
          .recent
          .to_a
          .group_by(&:business_id)
      end

      def google_credentials
        records[:google_credentials] ||= AicooGoogleCredential.all.to_a
      end

      def google_credentials_by_id
        records[:google_credentials_by_id] ||= google_credentials.index_by(&:id)
      end

      def serp_query_counts
        records[:serp_query_counts] ||= SerpQuery
          .where(enabled: true, status: "active")
          .group(:business_id)
          .count
      end

      def business_serp_keyword_counts
        records[:business_serp_keyword_counts] ||= BusinessSerpKeyword
          .where(status: "active")
          .group(:business_id)
          .count
      end
    end
  end
end
