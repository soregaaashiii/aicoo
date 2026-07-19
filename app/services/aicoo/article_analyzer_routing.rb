module Aicoo
  class ArticleAnalyzerRouting
    ACTIVE_ANALYZER = ArticleOpportunityDailyRun::MODEL_NAME
    ARTICLE_ACTION_TYPES = %w[
      article_create
      article_update
      new_article_candidate
      seo_article
      seo_improvement
    ].freeze
    LEGACY_GENERATION_SOURCES = %w[suelog_db business_analyzer ai_insight].freeze
    ACTIVE_STATUSES = ActionCandidate::STATUSES - ActionCandidate::INACTIVE_STATUSES

    Result = Data.define(
      :business,
      :active_analyzer,
      :new_analyzer_enabled,
      :legacy_generation_enabled,
      :routing_reason,
      :latest_new_analyzer_run_at,
      :latest_new_candidate_at,
      :latest_legacy_candidate_at,
      :legacy_candidates_created_last_24h,
      :new_candidates_created_last_24h,
      :today_new_candidate_count,
      :today_legacy_candidate_count,
      :fallback_source,
      :last_error,
      :next_required_action,
      :new_analyzer_step_status,
      :new_analyzer_candidate_count
    ) do
      def legacy_article_analyzer_skipped?
        !legacy_generation_enabled
      end

      def daily_run_metadata
        {
          "legacy_article_analyzer_skipped" => legacy_article_analyzer_skipped?,
          "legacy_article_analyzer_skip_reason" => legacy_article_analyzer_skipped? ? routing_reason : nil,
          "active_article_analyzer" => active_analyzer,
          "new_analyzer_step_status" => new_analyzer_step_status,
          "new_analyzer_candidate_count" => new_analyzer_candidate_count
        }.compact
      end

      def to_h
        {
          business_id: business&.id,
          business_name: business&.name,
          active_analyzer:,
          new_analyzer_enabled:,
          legacy_generation_enabled:,
          routing_reason:,
          latest_new_analyzer_run_at:,
          latest_new_candidate_at:,
          latest_legacy_candidate_at:,
          legacy_candidates_created_last_24h:,
          new_candidates_created_last_24h:,
          today_new_candidate_count:,
          today_legacy_candidate_count:,
          fallback_source:,
          last_error:,
          next_required_action:
        }
      end
    end

    def self.call(...)
      new(...).call
    end

    def self.suelog_business?(business)
      ArticleOpportunityDailyRun.target_business?(business)
    end

    def self.article_action_type?(action_type)
      action_type.to_s.in?(ARTICLE_ACTION_TYPES)
    end

    def initialize(business:)
      @business = business
    end

    def call
      target = self.class.suelog_business?(business)
      latest_step = latest_new_analyzer_step
      new_enabled = target && snapshot_infrastructure_available?
      legacy_enabled = !new_enabled

      Result.new(
        business:,
        active_analyzer: new_enabled ? ACTIVE_ANALYZER : "legacy_expected_value_analyzer",
        new_analyzer_enabled: new_enabled,
        legacy_generation_enabled: legacy_enabled,
        routing_reason: routing_reason(target:, new_enabled:),
        latest_new_analyzer_run_at: latest_step&.finished_at || latest_step&.updated_at,
        latest_new_candidate_at: latest_new_candidate&.created_at,
        latest_legacy_candidate_at: latest_legacy_candidate&.created_at,
        legacy_candidates_created_last_24h: legacy_candidate_scope.where(created_at: 24.hours.ago..).count,
        new_candidates_created_last_24h: new_candidate_scope.where(created_at: 24.hours.ago..).count,
        today_new_candidate_count: today_new_candidate_scope.count,
        today_legacy_candidate_count: today_legacy_candidate_scope.count,
        fallback_source: fallback_source,
        last_error: latest_step&.error_message.presence || Array(latest_step&.metadata.to_h["errors"]).first,
        next_required_action: next_required_action(latest_step:, new_enabled:),
        new_analyzer_step_status: latest_step&.status,
        new_analyzer_candidate_count: new_candidate_scope.count
      )
    end

    private

    attr_reader :business

    def snapshot_infrastructure_available?
      !!(
        defined?(Aicoo::ArticleAnalyticsSnapshotBuilder) &&
        defined?(Aicoo::ArticleOpportunityAnalyzer) &&
        defined?(Aicoo::ArticleOpportunityDailyRun)
      )
    end

    def routing_reason(target:, new_enabled:)
      return "not_suelog_business" unless target
      return "new_analyzer_active" if new_enabled

      "new_analyzer_unavailable"
    end

    def latest_new_analyzer_step
      return @latest_new_analyzer_step if defined?(@latest_new_analyzer_step)

      @latest_new_analyzer_step = AicooDailyRunStep
        .where(step_name: ArticleOpportunityDailyRun::STEP_NAME)
        .where("metadata ->> 'business_id' = ?", business.id.to_s)
        .order(created_at: :desc, id: :desc)
        .first
    end

    def latest_new_candidate
      @latest_new_candidate ||= new_candidate_scope.order(created_at: :desc, id: :desc).first
    end

    def latest_legacy_candidate
      @latest_legacy_candidate ||= legacy_candidate_scope.order(created_at: :desc, id: :desc).first
    end

    def new_candidate_scope
      business.action_candidates
        .where("metadata ->> 'value_model_name' = ?", ACTIVE_ANALYZER)
        .where("metadata ->> 'analysis_source' = ?", "article_analytics_snapshot")
    end

    def legacy_candidate_scope
      business.action_candidates
        .where(generation_source: LEGACY_GENERATION_SOURCES)
        .where(action_type: ARTICLE_ACTION_TYPES)
        .where("COALESCE(metadata ->> 'value_model_name', '') <> ?", ACTIVE_ANALYZER)
        .where(
          "generation_source IN (:legacy_generation_sources) OR metadata ->> 'suelog_site_insights' = 'true' OR metadata ->> 'external_source' = :suelog_db OR metadata ->> 'analyzer' LIKE :business_analyzer",
          legacy_generation_sources: LEGACY_GENERATION_SOURCES,
          suelog_db: "suelog_db",
          business_analyzer: "%BusinessAnalyzers%"
        )
    end

    def today_new_candidate_scope
      new_candidate_scope.where(status: ACTIVE_STATUSES)
    end

    def today_legacy_candidate_scope
      legacy_candidate_scope.where(status: ACTIVE_STATUSES)
    end

    def fallback_source
      return "article_opportunity_analyzer" if today_new_candidate_scope.exists?
      return "existing_legacy_candidate" if today_legacy_candidate_scope.exists?

      "today_fallback"
    end

    def next_required_action(latest_step:, new_enabled:)
      return "ArticleOpportunityAnalyzerを有効化してください" unless new_enabled
      return "Daily RunでArticleOpportunityAnalysisを実行してください" unless latest_step
      return "ArticleOpportunityAnalysisのエラーを確認してください" if latest_step.status == "failed"
      return "Today候補のstatusと重複抑制を確認してください" if today_new_candidate_scope.empty?

      "対応不要"
    end
  end
end
