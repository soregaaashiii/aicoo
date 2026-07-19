module Aicoo
  class IndependentActivityEligibility
    Result = Data.define(
      :included,
      :source_app,
      :source_model,
      :excluded_reason,
      :included_reason,
      :is_internal_event,
      :is_suelog_activity
    ) do
      def included?
        included
      end

      def metadata
        {
          "source_app" => source_app,
          "source_model" => source_model,
          "excluded_reason" => excluded_reason,
          "included_reason" => included_reason,
          "is_internal_event" => is_internal_event,
          "is_suelog_activity" => is_suelog_activity
        }
      end
    end

    SUELOG_SOURCE_APPS = %w[suelog sue-log 吸えログ].freeze
    USER_ACTIVITY_MODELS = %w[Shop Article].freeze
    INTERNAL_SOURCE_APPS = %w[aicoo system owner codex].freeze
    INTERNAL_SOURCE_MODELS = %w[
      ActionResult
      AicooDailyRun
      AicooDailyRunStep
      AicooLabLandingPage
      Business
      Calibration
    ].freeze
    INTERNAL_ACTIVITY_PATTERNS = [
      /\Aaction_result_/,
      /\Aactivity_api_(?:diagnostic|test|health)/,
      /\Alanding_page_/,
      /\Alp_(?:create|created|update|updated|publish|published|delete|deleted)\z/,
      /\Abusiness_(?:create|created|update|updated|delete|deleted)\z/,
      /\A(?:pipeline|daily_run|trigger|builder|calibration|learning|expected_value|today|owner|system)_/
    ].freeze
    USER_MUTATION_PATTERN = /(?:create|created|add|added|addition|update|updated|change|changed|delete|deleted|destroy|destroyed|remove|removed|improve|improved|improvement|verify|verified)\z/

    def self.call(activity_log)
      new(activity_log).call
    end

    def initialize(activity_log)
      @activity_log = activity_log
    end

    def call
      return excluded("internal_event", internal: true) if internal_event?
      return excluded("source_app_not_suelog") unless suelog_source?
      return excluded("unsupported_source_model") unless source_model.in?(USER_ACTIVITY_MODELS)
      return excluded("unsupported_activity_type") unless user_activity_type?

      Result.new(
        included: true,
        source_app: "suelog",
        source_model:,
        excluded_reason: nil,
        included_reason: "suelog_user_activity",
        is_internal_event: false,
        is_suelog_activity: true
      )
    end

    private

    attr_reader :activity_log

    def excluded(reason, internal: false)
      Result.new(
        included: false,
        source_app: normalized_source_app,
        source_model:,
        excluded_reason: reason,
        included_reason: nil,
        is_internal_event: internal,
        is_suelog_activity: false
      )
    end

    def internal_event?
      normalized_source_app.in?(INTERNAL_SOURCE_APPS) ||
        source_model.in?(INTERNAL_SOURCE_MODELS) ||
        INTERNAL_ACTIVITY_PATTERNS.any? { |pattern| pattern.match?(activity_type) }
    end

    def suelog_source?
      activity_log.source_app.to_s.downcase.in?(SUELOG_SOURCE_APPS)
    end

    def normalized_source_app
      suelog_source? ? "suelog" : activity_log.source_app.to_s.downcase.presence || "unknown"
    end

    def source_model
      @source_model ||= activity_log.resource_type.to_s.demodulize.presence || "unknown"
    end

    def activity_type
      @activity_type ||= activity_log.activity_type.to_s.downcase
    end

    def user_activity_type?
      USER_MUTATION_PATTERN.match?(activity_type)
    end
  end
end
