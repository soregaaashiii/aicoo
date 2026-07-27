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

        key = source_key.to_s
        return data_source_cost_profiles[key] if data_source_cost_profiles.key?(key)

        data_source_cost_profiles[key] = yield
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

      def fetch(key)
        return yield unless active?

        records[key] = yield unless records.key?(key)
        records[key]
      end

      def revenue_event_available(business)
        return yield unless active?

        revenue_event_business_ids.include?(business&.id)
      end

      def revenue_event_average_amount(business)
        return yield unless active?

        revenue_event_average_amounts[business&.id]
      end

      def owner_active_action_candidates
        return load_owner_active_action_candidates unless active?

        records[:owner_active_action_candidates] ||= load_owner_active_action_candidates
      end

      def owner_active_action_candidates_by_business_id
        return owner_active_action_candidates.group_by(&:business_id) unless active?

        records[:owner_active_action_candidates_by_business_id] ||= owner_active_action_candidates.group_by(&:business_id)
      end

      def owner_real_businesses
        return load_owner_real_businesses unless active?

        records[:owner_real_businesses] ||= load_owner_real_businesses
      end

      def normalized_metadata(record)
        metadata = record&.metadata.to_h
        return metadata.deep_stringify_keys unless active?

        normalized_metadata_by_record[record.object_id] ||= if record.persisted? && !record.will_save_change_to_metadata?
          metadata
        else
          metadata.deep_stringify_keys
        end
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

      def revenue_event_business_ids
        records[:revenue_event_business_ids] ||= RevenueEvent.revenue.distinct.pluck(:business_id).to_set
      end

      def revenue_event_average_amounts
        records[:revenue_event_average_amounts] ||= RevenueEvent.revenue.group(:business_id).average(:amount)
      end

      def normalized_metadata_by_record
        records[:normalized_metadata_by_record] ||= {}
      end

      def load_owner_active_action_candidates
        ActionCandidate
          .active_for_ranking
          .preload(
            :action_result,
            :action_execution,
            auto_revision_tasks: :business,
            business: [ :business_execution_profile, :business_data_source_settings ]
          )
          .order(updated_at: :desc)
          .to_a
      end

      def load_owner_real_businesses
        Business.real_businesses.order(:name).to_a
      end
    end
  end
end
