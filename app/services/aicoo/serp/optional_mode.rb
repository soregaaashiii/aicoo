module Aicoo
  module Serp
    class OptionalMode
      SERP_DEPENDENT_STEPS = %w[
        serp_fetch
        keyword_discovery
        competitor_serp_analysis
        serp_based_idea_generation
      ].freeze

      SERP_INDEPENDENT_STEPS = %w[
        ga4_fetch
        gsc_fetch
        lp_snapshot
        business_metric_daily
        action_candidate_generation
        auto_revision_queue
        action_result_evaluation
        activity_learning
        resource_control
        lifecycle_evaluation
      ].freeze

      WARNING_REASON = "serp_optional_missing".freeze
      WARNING_MESSAGE = "SERP API Key未設定のため、SERP依存の探索・SEO競合分析のみスキップします。既存データによる改善ループは継続します。".freeze

      Result = Data.define(
        :enabled,
        :api_key_configured,
        :status,
        :reason,
        :message,
        :dependent_steps,
        :independent_steps,
        :provider,
        :profile
      ) do
        def missing_key?
          enabled && !api_key_configured
        end

        def warning?
          status == "warning"
        end
      end

      def self.call
        new.call
      end

      def call
        Result.new(
          enabled: profile.enabled?,
          api_key_configured: api_key_configured?,
          status: status,
          reason: reason,
          message: message,
          dependent_steps: SERP_DEPENDENT_STEPS,
          independent_steps: SERP_INDEPENDENT_STEPS,
          provider: provider,
          profile: profile
        )
      end

      private

      def profile
        @profile ||= begin
          DataSourceCostProfile.ensure_defaults!
          DataSourceCostProfile.for_source("serp")
        end
      end

      def api_key_configured?
        ENV["SERPER_API_KEY"].present? || ENV["SERP_API_KEY"].present? || profile.api_key_configured?
      end

      def status
        return "disabled" unless profile.enabled?
        return "configured" if api_key_configured?

        "warning"
      end

      def reason
        return "serp_disabled" unless profile.enabled?
        return "serp_configured" if api_key_configured?

        WARNING_REASON
      end

      def message
        return "SERPは無効です。SERP依存stepだけをスキップします。" unless profile.enabled?
        return "SERP API Key設定済みです。SERP依存stepを実行できます。" if api_key_configured?

        WARNING_MESSAGE
      end

      def provider
        ENV["AICOO_SERP_PROVIDER"].presence || "serper"
      end
    end
  end
end
