module Aicoo
  class BusinessExpectedValue
    ACTION_CAP_YEN = 250_000
    OPPORTUNITY_CAP_YEN = 250_000
    BUSINESS_SHORT_TERM_CAP_YEN = 1_000_000
    NEW_BUSINESS_STANDARD_90D_PROFIT_YEN = 30_000
    NEW_BUSINESS_STANDARD_SUCCESS_PROBABILITY = 0.15.to_d
    NEW_BUSINESS_STANDARD_VALIDATION_COST_YEN = 5_000
    CALCULATION_VERSION = "business_expected_value_v1".freeze

    Result = Data.define(
      :business,
      :raw_candidate_sum_yen,
      :unique_opportunity_count,
      :duplicate_candidate_count,
      :duplicate_adjustment_yen,
      :cap_adjustment_yen,
      :confidence_adjustment_yen,
      :cost_yen,
      :expected_revenue_value_yen,
      :expected_learning_value_yen,
      :expected_total_value_yen,
      :calculation_method,
      :confidence,
      :opportunities,
      :new_business_value
    )
    OpportunityRow = Data.define(
      :key,
      :raw_sum_yen,
      :cap_yen,
      :final_value_yen,
      :candidate_ids,
      :duplicate_candidate_count,
      :duplicate_adjustment_yen,
      :cap_adjustment_yen,
      :confidence_adjustment_yen,
      :cost_yen
    )
    NewBusinessValue = Data.define(
      :estimated_90d_profit_yen,
      :validation_success_probability,
      :validation_cost_yen,
      :final_expected_value_yen,
      :calculation_method,
      :confidence,
      :missing_inputs
    )

    def self.call(business)
      new(business).call
    end

    def initialize(business)
      @business = business
    end

    def call
      return new_business_result if exploration_business?

      existing_business_result
    end

    private

    attr_reader :business

    def existing_business_result
      rows = grouped_opportunities.map { |key, candidates| build_opportunity_row(key, candidates) }
      raw_candidate_sum_yen = active_candidates.sum { |candidate| raw_candidate_value_yen(candidate) }
      duplicate_candidate_count = rows.sum(&:duplicate_candidate_count)
      duplicate_adjustment_yen = rows.sum(&:duplicate_adjustment_yen)
      opportunity_total_yen = rows.sum(&:final_value_yen)
      business_capped_revenue_yen = [ opportunity_total_yen, BUSINESS_SHORT_TERM_CAP_YEN ].min
      business_cap_adjustment_yen = [ opportunity_total_yen - business_capped_revenue_yen, 0 ].max
      cap_adjustment_yen = rows.sum(&:cap_adjustment_yen) + business_cap_adjustment_yen
      confidence_adjustment_yen = rows.sum(&:confidence_adjustment_yen)
      cost_yen = rows.sum(&:cost_yen)
      expected_revenue_value_yen = business_capped_revenue_yen - cost_yen
      expected_learning_value_yen = [ active_candidates.sum { |candidate| candidate.expected_learning_value_yen.to_i }, 100_000 ].min
      expected_total_value_yen = expected_revenue_value_yen + expected_learning_value_yen

      result = Result.new(
        business:,
        raw_candidate_sum_yen:,
        unique_opportunity_count: rows.size,
        duplicate_candidate_count:,
        duplicate_adjustment_yen:,
        cap_adjustment_yen:,
        confidence_adjustment_yen:,
        cost_yen:,
        expected_revenue_value_yen:,
        expected_learning_value_yen:,
        expected_total_value_yen:,
        calculation_method: "opportunity_grouped_capped_sum",
        confidence: rows.any? ? average(rows.map { |row| row.final_value_yen.positive? ? 0.7 : 0.4 }) : 0.3,
        opportunities: rows,
        new_business_value: nil
      )
      persist_business_value!(result)
      result
    end

    def new_business_result
      value = new_business_value
      result = Result.new(
        business:,
        raw_candidate_sum_yen: value.estimated_90d_profit_yen,
        unique_opportunity_count: 1,
        duplicate_candidate_count: 0,
        duplicate_adjustment_yen: 0,
        cap_adjustment_yen: 0,
        confidence_adjustment_yen: ((value.estimated_90d_profit_yen.to_d * (1 - value.validation_success_probability)).round),
        cost_yen: value.validation_cost_yen,
        expected_revenue_value_yen: value.final_expected_value_yen,
        expected_learning_value_yen: 0,
        expected_total_value_yen: value.final_expected_value_yen,
        calculation_method: value.calculation_method,
        confidence: value.confidence,
        opportunities: [],
        new_business_value: value
      )
      persist_business_value!(result)
      result
    end

    def active_candidates
      @active_candidates ||= business.action_candidates.active_for_ranking.to_a
    end

    def grouped_opportunities
      active_candidates.group_by { |candidate| opportunity_key_for(candidate) }
    end

    def build_opportunity_row(key, candidates)
      raw_sum_yen = candidates.sum { |candidate| raw_candidate_value_yen(candidate) }
      cost_yen = candidates.sum { |candidate| candidate.cost_yen.to_i }
      action_capped_values = candidates.to_h do |candidate|
        [ candidate, [ raw_candidate_value_yen(candidate), ACTION_CAP_YEN ].min ]
      end
      action_cap_adjustment_yen = candidates.sum do |candidate|
        [ raw_candidate_value_yen(candidate) - action_capped_values.fetch(candidate), 0 ].max
      end
      confidence_adjusted_values = candidates.to_h do |candidate|
        value = action_capped_values.fetch(candidate)
        [ candidate, (value.to_d * confidence_for(candidate)).round ]
      end
      confidence_adjustment_yen = action_capped_values.values.sum - confidence_adjusted_values.values.sum
      confidence_adjusted_sum = confidence_adjusted_values.values.sum
      final_value_yen = [ confidence_adjusted_sum, OPPORTUNITY_CAP_YEN ].min
      opportunity_cap_adjustment_yen = [ confidence_adjusted_sum - final_value_yen, 0 ].max
      duplicate_adjustment_yen = candidates.size > 1 ? [ raw_sum_yen - candidates.map { |candidate| raw_candidate_value_yen(candidate) }.max, 0 ].max : 0

      row = OpportunityRow.new(
        key:,
        raw_sum_yen:,
        cap_yen: OPPORTUNITY_CAP_YEN,
        final_value_yen:,
        candidate_ids: candidates.map(&:id),
        duplicate_candidate_count: [ candidates.size - 1, 0 ].max,
        duplicate_adjustment_yen:,
        cap_adjustment_yen: action_cap_adjustment_yen + opportunity_cap_adjustment_yen,
        confidence_adjustment_yen:,
        cost_yen:
      )
      persist_candidate_value_models!(key, candidates, row)
      row
    end

    def raw_candidate_value_yen(candidate)
      metadata = candidate.metadata.to_h
      metadata.dig("value_model", "raw_expected_value_yen").presence&.to_i ||
        metadata["raw_expected_value_yen"].presence&.to_i ||
        candidate.expected_profit_yen.to_i
    end

    def confidence_for(candidate)
      metadata = candidate.metadata.to_h
      value_model = metadata["value_model"].to_h
      confidence = value_model["confidence"].presence || candidate.success_probability.presence || 0.5
      confidence.to_d.clamp(0.1.to_d, 1.to_d)
    end

    def opportunity_key_for(candidate)
      metadata = candidate.metadata.to_h
      raw_key = [
        metadata["opportunity_group"],
        metadata["opportunity_key"],
        metadata.dig("opportunity", "key"),
        metadata.dig("evidence", "query"),
        metadata["query"],
        metadata["keyword"],
        metadata["source_query"],
        metadata.dig("article_candidate", "keyword")
      ].compact_blank.first

      raw_key ||= [
        metadata["target_url"],
        metadata["target_url_or_identifier"],
        metadata.dig("action_plan", "target_url_or_identifier"),
        metadata.dig("action_plan", "target"),
        metadata["search_intent"],
        metadata.dig("evidence", "issue_type"),
        metadata["metric_rule"],
        metadata["serp_analysis_id"],
        metadata["gsc_opportunity_id"]
      ].compact_blank.first

      normalized = raw_key.presence || "#{candidate.action_type}:#{candidate.title}"
      normalized.downcase
        .unicode_normalize(:nfkc)
        .gsub(%r{https?://}, "")
        .gsub(/[[:space:]　]+/, "")
        .gsub(/[?#].*\z/, "")
        .presence || "unknown"
    end

    def persist_candidate_value_models!(key, candidates, row)
      duplicate_ids = row.candidate_ids
      candidates.each do |candidate|
        metadata = candidate.metadata.to_h
        raw_value = raw_candidate_value_yen(candidate)
        action_capped_value = [ raw_value, ACTION_CAP_YEN ].min
        payload = {
          "raw_expected_value_yen" => raw_value,
          "capped_expected_value_yen" => action_capped_value,
          "cap_reason" => cap_reason_for(raw_value, row),
          "opportunity_group" => key,
          "duplicate_candidates" => duplicate_ids - [ candidate.id ],
          "opportunity_cap_yen" => OPPORTUNITY_CAP_YEN,
          "action_cap_yen" => ACTION_CAP_YEN,
          "business_short_term_cap_yen" => BUSINESS_SHORT_TERM_CAP_YEN,
          "calculation_version" => CALCULATION_VERSION
        }
        next if metadata["business_value_model"] == payload

        candidate.update_columns(
          metadata: metadata.merge("business_value_model" => payload),
          updated_at: Time.current
        )
      end
    end

    def persist_business_value!(result)
      metadata = business.metadata.to_h
      payload = {
        "raw_candidate_sum_yen" => result.raw_candidate_sum_yen,
        "unique_opportunity_count" => result.unique_opportunity_count,
        "duplicate_candidate_count" => result.duplicate_candidate_count,
        "duplicate_adjustment_yen" => result.duplicate_adjustment_yen,
        "cap_adjustment_yen" => result.cap_adjustment_yen,
        "confidence_adjustment_yen" => result.confidence_adjustment_yen,
        "cost_yen" => result.cost_yen,
        "expected_revenue_value_yen" => result.expected_revenue_value_yen,
        "expected_learning_value_yen" => result.expected_learning_value_yen,
        "final_expected_value_yen" => result.expected_total_value_yen,
        "calculation_method" => result.calculation_method,
        "confidence" => result.confidence.to_f,
        "calculation_version" => CALCULATION_VERSION,
        "new_business_value" => new_business_payload(result.new_business_value),
        "calculated_at" => Time.current.iso8601
      }.compact

      business.update_columns(
        metadata: metadata.merge("business_value_model" => payload),
        updated_at: Time.current
      )
    end

    def new_business_payload(value)
      return unless value

      {
        "estimated_90d_profit_yen" => value.estimated_90d_profit_yen,
        "validation_success_probability" => value.validation_success_probability.to_f,
        "validation_cost_yen" => value.validation_cost_yen,
        "final_expected_value_yen" => value.final_expected_value_yen,
        "calculation_method" => value.calculation_method,
        "confidence" => value.confidence,
        "missing_inputs" => value.missing_inputs
      }
    end

    def cap_reason_for(raw_value, row)
      reasons = []
      reasons << "action_cap" if raw_value > ACTION_CAP_YEN
      reasons << "opportunity_cap" if row.cap_adjustment_yen.positive?
      reasons << "duplicate_opportunity" if row.duplicate_candidate_count.positive?
      reasons.presence || [ "none" ]
    end

    def new_business_value
      metadata = business.metadata.to_h
      missing_inputs = []
      estimated_90d_profit_yen = first_positive_integer(
        metadata["estimated_90d_profit_yen"],
        metadata["expected_90d_profit_yen"],
        metadata["expected_value_yen"],
        metadata["expected_profit_yen"]
      )
      unless estimated_90d_profit_yen.positive?
        missing_inputs << "estimated_90d_profit_yen"
        estimated_90d_profit_yen = NEW_BUSINESS_STANDARD_90D_PROFIT_YEN
      end

      success_probability = first_positive_decimal(metadata["validation_success_probability"], metadata["success_probability"])
      unless success_probability.positive?
        missing_inputs << "validation_success_probability"
        success_probability = NEW_BUSINESS_STANDARD_SUCCESS_PROBABILITY
      end

      validation_cost_yen = first_positive_integer(metadata["validation_cost_yen"], metadata["initial_cost_yen"])
      unless validation_cost_yen.positive?
        missing_inputs << "validation_cost_yen"
        validation_cost_yen = NEW_BUSINESS_STANDARD_VALIDATION_COST_YEN
      end

      final_expected_value_yen = (estimated_90d_profit_yen.to_d * success_probability - validation_cost_yen).round

      NewBusinessValue.new(
        estimated_90d_profit_yen:,
        validation_success_probability: success_probability,
        validation_cost_yen:,
        final_expected_value_yen:,
        calculation_method: missing_inputs.empty? ? "new_business_metadata" : "new_business_fallback_standard_90d",
        confidence: missing_inputs.empty? ? "medium" : "low",
        missing_inputs:
      )
    end

    def exploration_business?
      business.business_type == "exploration" || business.status.in?(%w[discovered draft exploring])
    end

    def first_positive_integer(*values)
      values.map { |value| value.to_i }.find(&:positive?) || 0
    end

    def first_positive_decimal(*values)
      values.map { |value| value.to_d }.find(&:positive?) || 0.to_d
    end

    def average(values)
      return 0.to_d if values.blank?

      values.sum.to_d / values.size
    end
  end
end
