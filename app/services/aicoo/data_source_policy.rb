module Aicoo
  class DataSourcePolicy
    SourceState = Data.define(:key, :label, :category, :enabled, :reason, :setting) do
      def used? = enabled
      def unused? = !enabled
      def internal? = category == "internal"
      def external? = category == "external"
    end

    INTERNAL_SOURCES = {
      "ga4" => "GA4",
      "gsc" => "GSC",
      "internal" => "Internal"
    }.freeze

    EXTERNAL_SOURCES = {
      "serp" => "SERP",
      "reddit" => "Reddit",
      "x" => "X",
      "news" => "News",
      "web_search" => "Web Search",
      "external_ranking" => "外部ランキング"
    }.freeze
    VISIBLE_SOURCE_KEYS = %w[ga4 gsc internal serp reddit x news].freeze

    def self.for(business)
      new(business)
    end

    def initialize(business)
      @business = business
    end

    def enabled?(source_key, context: :existing_business_improvement)
      key = normalize_source_key(source_key)
      return false if business.blank?
      return internal_enabled?(key) if INTERNAL_SOURCES.key?(key)
      return external_enabled?(key, context:) if EXTERNAL_SOURCES.key?(key)

      false
    end

    def source_states(context: :existing_business_improvement)
      internal_source_states(context:) + external_source_states(context:)
    end

    def used_source_states(context: :existing_business_improvement)
      source_states(context:).select(&:used?)
    end

    def unused_source_states(context: :existing_business_improvement)
      source_states(context:).select(&:unused?)
    end

    def visible_source_states(context: :existing_business_improvement)
      source_states(context:).select { |source| source.key.in?(VISIBLE_SOURCE_KEYS) }
    end

    def exploration_business?
      business&.business_type == "exploration" ||
        business&.metadata.to_h["business_type"].to_s == "exploration" ||
        business&.metadata.to_h["analysis_mode"].to_s == "exploration"
    end

    private

    attr_reader :business

    def internal_source_states(context:)
      INTERNAL_SOURCES.map do |key, label|
        enabled = enabled?(key, context:)
        SourceState.new(
          key:,
          label:,
          category: "internal",
          enabled:,
          reason: enabled ? "既存Business改善で使用します。" : "Business個別設定で無効です。",
          setting: setting_for(key)
        )
      end
    end

    def external_source_states(context:)
      EXTERNAL_SOURCES.map do |key, label|
        enabled = enabled?(key, context:)
        SourceState.new(
          key:,
          label:,
          category: "external",
          enabled:,
          reason: external_reason(key, enabled:, context:),
          setting: setting_for(key)
        )
      end
    end

    def internal_enabled?(key)
      return true if key == "internal"

      setting = setting_for(key)
      setting.nil? ? true : setting.enabled?
    end

    def external_enabled?(key, context:)
      setting = setting_for(key)
      return existing_business_override_enabled?(setting) if context.to_s == "existing_business_improvement"
      return false unless exploration_business?

      setting.nil? ? true : setting.enabled?
    end

    def existing_business_override_enabled?(setting)
      return false unless setting&.enabled?

      policy = setting.metadata.to_h.fetch("analysis_policy", {})
      ActiveModel::Type::Boolean.new.cast(policy["allow_existing_business_improvement"])
    end

    def external_reason(key, enabled:, context:)
      return "検証済みのBusiness個別設定で既存Business改善への利用を許可しています。" if enabled && context.to_s == "existing_business_improvement"
      return "Business Type=explorationの新規事業探索で使用可能です。" if enabled && exploration_business?
      return "Business個別設定で無効です。" if exploration_business? && setting_for(key)&.enabled? == false

      "既存Business改善では使用しません。新規事業探索または検証済み個別設定のみ使用可能です。"
    end

    def setting_for(key)
      return @settings_by_key[key] if defined?(@settings_by_key) && @settings_by_key.key?(key)

      @settings_by_key ||= business.business_data_source_settings.index_by(&:source_key)
      @settings_by_key[key]
    end

    def normalize_source_key(source_key)
      source_key.to_s.strip.downcase
    end
  end
end
