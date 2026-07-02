module Aicoo
  class ActionCandidateBusinessPromoter
    Result = Data.define(:business, :created, :promoted, :message)

    NEW_BUSINESS_ACTION_TYPES = %w[new_business lp_experiment market_test build_lp build_mvp].freeze
    NEW_BUSINESS_SOURCES = %w[serp integrated_decision ai_business ai_cross_business].freeze

    def initialize(action_candidate)
      @action_candidate = action_candidate
    end

    def call
      return Result.new(business: action_candidate.business, created: false, promoted: false, message: nil) unless new_business_candidate?

      existing = existing_business
      if existing
        link_candidate!(existing, created: false)
        return Result.new(
          business: existing,
          created: false,
          promoted: true,
          message: "既存Businessに紐付けました: #{existing.name}"
        )
      end

      business = Business.create!(business_attributes)
      link_candidate!(business, created: true)
      Result.new(
        business:,
        created: true,
        promoted: true,
        message: "Businessを作成しました: #{business.name}"
      )
    end

    private

    attr_reader :action_candidate

    def new_business_candidate?
      metadata = action_candidate.metadata.to_h
      return true if metadata["candidate_kind"] == "new_business"
      return true if action_candidate.department == "new_business"
      return true if action_candidate.action_type.in?(%w[new_business lp_experiment market_test])

      action_candidate.action_type.in?(NEW_BUSINESS_ACTION_TYPES) &&
        action_candidate.generation_source.in?(NEW_BUSINESS_SOURCES)
    end

    def existing_business
      Business.real_businesses.find_by("LOWER(name) = ?", business_name.downcase)
    end

    def link_candidate!(business, created:)
      action_candidate.business = business
      action_candidate.metadata = action_candidate.metadata.to_h.merge(
        "business_promotion" => {
          "promoted" => true,
          "created_business" => created,
          "business_id" => business.id,
          "source" => action_candidate.generation_source,
          "promoted_at" => Time.current.iso8601
        }
      )
    end

    def business_attributes
      {
        name: business_name,
        description: business_description,
        category: business_category,
        status: "idea",
        source: business_source,
        created_by_aicoo: true,
        launched: false,
        daily_run_enabled: true,
        serp_enabled: true,
        auto_revision_mode: "manual",
        lifecycle_stage: "lp_validation",
        resource_status: "active",
        business_type: "landing_page",
        metadata: business_metadata
      }
    end

    def business_name
      base = action_candidate.metadata.to_h["business_name"].presence ||
             action_candidate.metadata.to_h["service_name"].presence ||
             action_candidate.title.to_s
      name = base.squish.presence || "新規事業候補 #{action_candidate.id}"
      return "#{name} 事業" if name.in?(Business::SYSTEM_BUSINESS_NAMES)

      name
    end

    def business_description
      [
        action_candidate.description.presence || action_candidate.execution_prompt.presence,
        labeled_text("解決課題", action_candidate.metadata.to_h["problem"]),
        labeled_text("想定顧客", action_candidate.metadata.to_h["target_customer"]),
        labeled_text("収益モデル", action_candidate.metadata.to_h["revenue_model"]),
        labeled_text("検証ステップ", action_candidate.metadata.to_h["validation_step"]),
        labeled_text("根拠検索クエリ", action_candidate.metadata.to_h["source_query"])
      ].compact_blank.join("\n\n")
    end

    def business_category
      action_candidate.metadata.to_h["category"].presence ||
        action_candidate.metadata.to_h["market_category"].presence ||
        action_candidate.action_type.presence ||
        "new_business"
    end

    def business_source
      case action_candidate.generation_source
      when "serp" then "serp"
      when "integrated_decision" then "integrated_decision"
      else "ai_suggested"
      end
    end

    def business_metadata
      {
        "created_from" => "action_candidate",
        "action_candidate_id" => action_candidate.id,
        "generation_source" => action_candidate.generation_source,
        "candidate_kind" => action_candidate.metadata.to_h["candidate_kind"].presence || "new_business",
        "source_query" => action_candidate.metadata.to_h["source_query"],
        "serp_run_id" => action_candidate.metadata.to_h["serp_run_id"],
        "serp_analysis_id" => action_candidate.metadata.to_h["serp_analysis_id"],
        "expected_profit_yen" => action_candidate.expected_profit_yen,
        "expected_hours" => action_candidate.expected_hours&.to_s
      }.compact
    end

    def labeled_text(label, value)
      return if value.blank?

      "#{label}: #{value}"
    end
  end
end
