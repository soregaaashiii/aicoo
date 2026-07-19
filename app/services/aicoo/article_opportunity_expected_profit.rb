module Aicoo
  class ArticleOpportunityExpectedProfit
    MODEL_NAME = "article_opportunity_expected_profit_v1".freeze
    CALIBRATION_VERSION = "2026-07-19".freeze
    SNAPSHOT_SOURCE_TYPE = "article_analytics".freeze
    INITIAL_COEFFICIENTS = {
      "ctr_gain_rate" => 0.035,
      "rank_gain_positions" => 2.0,
      "click_value_yen" => 500,
      "shop_visit_rate" => 0.18,
      "conversion_rate" => 0.04,
      "profit_per_conversion_yen" => 12_000,
      "internal_link_pageview_lift_rate" => 0.10,
      "content_ctr_gain_rate" => 0.02,
      "owner_hourly_cost_yen" => 1_500,
      "fallback_impressions" => 5_000,
      "fallback_pageviews" => 5_000
    }.freeze

    Result = Data.define(
      :candidate_id,
      :improvement_type,
      :expected_profit_yen,
      :expected_revenue_yen,
      :work_cost_yen,
      :expected_ctr_gain,
      :expected_click_gain,
      :expected_conversion_gain,
      :success_probability,
      :confidence,
      :model_source,
      :learning_source,
      :calibration_version,
      :metadata
    )

    def self.call(candidate)
      new(candidate).call
    end

    def initialize(candidate)
      @candidate = candidate
      @metadata = candidate.metadata.to_h.deep_stringify_keys
      @assumed_fields = []
      @assumption_reasons = {}
      @input_sources = {}
    end

    def call
      improvement_type = resolved_improvement_type
      metrics = resolved_metrics
      coefficients = resolved_coefficients
      success_probability = calibrated_success_probability(improvement_type)
      work_hours = decimal(first_present(metadata["estimated_work_hours"], candidate.expected_hours, 1))
      work_cost = work_hours * coefficients.fetch("owner_hourly_cost_yen")
      estimate = estimate_for(improvement_type, metrics, coefficients)
      expected_revenue = (estimate.fetch(:expected_revenue_yen) * profit_factor_for(improvement_type)).round
      expected_profit = (expected_revenue * success_probability - work_cost).round
      source = model_source_for(improvement_type)
      confidence = confidence_for(source)

      Result.new(
        candidate_id: candidate.id,
        improvement_type:,
        expected_profit_yen: expected_profit.to_i,
        expected_revenue_yen: expected_revenue.to_i,
        work_cost_yen: work_cost.round.to_i,
        expected_ctr_gain: estimate.fetch(:expected_ctr_gain).to_f.round(4),
        expected_click_gain: estimate.fetch(:expected_click_gain).to_f.round(2),
        expected_conversion_gain: estimate.fetch(:expected_conversion_gain).to_f.round(4),
        success_probability: success_probability.to_f.round(4),
        confidence: confidence.to_f.round(4),
        model_source: source,
        learning_source: learning_source_for(improvement_type, source),
        calibration_version: CALIBRATION_VERSION,
        metadata: result_metadata(improvement_type, metrics, coefficients, estimate, expected_revenue, expected_profit, work_cost, success_probability, confidence, source)
      )
    end

    private

    attr_reader :candidate, :metadata, :assumed_fields, :assumption_reasons, :input_sources

    def resolved_improvement_type
      first_present(
        metadata["opportunity_type"],
        metadata["improvement_type"],
        metadata.dig("execution_brief", "target", "improvement_type"),
        metadata.dig("opportunities", 0, "opportunity_type"),
        "content_update"
      ).to_s
    end

    def resolved_metrics
      snapshot_payload = snapshot&.payload.to_h.deep_stringify_keys
      evidence = metadata["evidence"].to_h
      {
        "gsc" => metrics_from(snapshot_payload, evidence, "gsc"),
        "ga4" => metrics_from(snapshot_payload, evidence, "ga4"),
        "shop_click" => metrics_from(snapshot_payload, evidence, "shop_click"),
        "learning" => metrics_from(snapshot_payload, evidence, "learning")
      }
    end

    def metrics_from(snapshot_payload, evidence, key)
      snapshot_value = snapshot_payload[key].to_h
      evidence_value = evidence[key].to_h
      source = snapshot_value.present? ? "article_analytics_snapshot" : "candidate_metadata"
      input_sources[key] = source
      snapshot_value.presence || evidence_value
    end

    def snapshot
      return @snapshot if defined?(@snapshot)

      snapshot_id = metadata["snapshot_id"]
      @snapshot =
        if snapshot_id.present?
          AicooDataSnapshot.where(source_type: SNAPSHOT_SOURCE_TYPE).find_by(id: snapshot_id)
        end
    end

    def resolved_coefficients
      {
        "ctr_gain_rate" => coefficient("ctr_gain_rate", business_metadata_keys: %w[ctr_gain_rate article_ctr_gain_rate]),
        "rank_gain_positions" => coefficient("rank_gain_positions", business_metadata_keys: %w[rank_gain_positions article_rank_gain_positions]),
        "click_value_yen" => coefficient("click_value_yen", business_metadata_keys: %w[click_value_yen article_click_value_yen]),
        "shop_visit_rate" => coefficient("shop_visit_rate", business_metadata_keys: %w[shop_visit_rate article_shop_visit_rate]),
        "conversion_rate" => coefficient("conversion_rate", business_metadata_keys: %w[conversion_rate cv_rate article_conversion_rate]),
        "profit_per_conversion_yen" => coefficient("profit_per_conversion_yen", business_metadata_keys: %w[profit_per_conversion_yen revenue_per_conversion_yen article_profit_per_conversion_yen]),
        "internal_link_pageview_lift_rate" => coefficient("internal_link_pageview_lift_rate", business_metadata_keys: %w[internal_link_pageview_lift_rate]),
        "content_ctr_gain_rate" => coefficient("content_ctr_gain_rate", business_metadata_keys: %w[content_ctr_gain_rate]),
        "owner_hourly_cost_yen" => coefficient("owner_hourly_cost_yen", business_metadata_keys: %w[owner_hourly_cost_yen])
      }
    end

    def coefficient(key, business_metadata_keys:)
      business_metadata_keys.each do |metadata_key|
        value = business_metadata[metadata_key]
        if value.present?
          input_sources[key] = "business_metadata.#{metadata_key}"
          return decimal(value)
        end
      end

      assumed_fields << key
      assumption_reasons[key] = "existing_initial_coefficient"
      input_sources[key] = "initial_coefficients"
      decimal(INITIAL_COEFFICIENTS.fetch(key))
    end

    def business_metadata
      @business_metadata ||= candidate.business&.metadata.to_h.deep_stringify_keys
    end

    def estimate_for(improvement_type, metrics, coefficients)
      case improvement_type
      when "ctr_improvement"
        estimate_ctr_improvement(metrics, coefficients)
      when "rank_improvement"
        estimate_rank_improvement(metrics, coefficients)
      when "internal_link_addition"
        estimate_internal_link(metrics, coefficients)
      when "content_update"
        estimate_content_update(metrics, coefficients)
      else
        estimate_content_update(metrics, coefficients)
      end
    end

    def estimate_ctr_improvement(metrics, coefficients)
      impressions = metric_value(metrics, "gsc", "impressions", fallback: INITIAL_COEFFICIENTS.fetch("fallback_impressions"))
      current_ctr = normalize_rate(metric_value(metrics, "gsc", "ctr", fallback: 0.01))
      expected_ctr_gain = [ coefficients.fetch("ctr_gain_rate"), [ target_ctr_for(metric_value(metrics, "gsc", "average_position", fallback: 20)) - current_ctr, 0.to_d ].max ].max
      expected_click_gain = impressions * expected_ctr_gain
      conversion_estimate(expected_click_gain, expected_ctr_gain, coefficients)
    end

    def estimate_rank_improvement(metrics, coefficients)
      impressions = metric_value(metrics, "gsc", "impressions", fallback: INITIAL_COEFFICIENTS.fetch("fallback_impressions"))
      position = metric_value(metrics, "gsc", "average_position", fallback: 20)
      current_ctr = normalize_rate(metric_value(metrics, "gsc", "ctr", fallback: rank_improvement_ctr_for(position)))
      improved_position = [ position - coefficients.fetch("rank_gain_positions"), 1.to_d ].max
      rank_ctr_gain = [ rank_improvement_ctr_for(improved_position) - rank_improvement_ctr_for(position), 0.to_d ].max
      expected_ctr_gain = coefficients.fetch("content_ctr_gain_rate") + rank_ctr_gain
      impression_gain_rate = rank_impression_gain_rate(metrics, position, improved_position)
      expected_impressions_after = impressions * (1 + impression_gain_rate)
      expected_ctr_after = current_ctr + expected_ctr_gain
      click_gain_from_ctr = impressions * expected_ctr_gain
      click_gain_from_impressions = [ expected_impressions_after - impressions, 0.to_d ].max * expected_ctr_after
      expected_click_gain = click_gain_from_ctr + click_gain_from_impressions
      conversion_estimate(expected_click_gain, expected_ctr_gain, coefficients).merge(
        rank_diagnostics: {
          current_position: position.to_f.round(2),
          expected_position_after_rank_gain: improved_position.to_f.round(2),
          current_impressions: impressions.to_f.round(2),
          expected_impressions_after_rank_gain: expected_impressions_after.to_f.round(2),
          impression_gain_rate: impression_gain_rate.to_f.round(4),
          current_ctr: current_ctr.to_f.round(4),
          expected_ctr_after_rank_gain: expected_ctr_after.to_f.round(4),
          click_gain_from_ctr: click_gain_from_ctr.to_f.round(2),
          click_gain_from_impressions: click_gain_from_impressions.to_f.round(2),
          total_expected_click_gain: expected_click_gain.to_f.round(2)
        }
      )
    end

    def estimate_content_update(metrics, coefficients)
      impressions = metric_value(metrics, "gsc", "impressions", fallback: INITIAL_COEFFICIENTS.fetch("fallback_impressions"))
      expected_ctr_gain = coefficients.fetch("content_ctr_gain_rate")
      expected_click_gain = impressions * expected_ctr_gain
      conversion_estimate(expected_click_gain, expected_ctr_gain, coefficients)
    end

    def estimate_internal_link(metrics, coefficients)
      pageviews = metric_value(metrics, "ga4", "pageviews", fallback: INITIAL_COEFFICIENTS.fetch("fallback_pageviews"))
      expected_pageview_gain = pageviews * coefficients.fetch("internal_link_pageview_lift_rate")
      expected_click_gain = expected_pageview_gain * coefficients.fetch("shop_visit_rate")
      conversion_estimate(expected_click_gain, 0.to_d, coefficients)
    end

    def conversion_estimate(expected_click_gain, expected_ctr_gain, coefficients)
      expected_conversion_gain = expected_click_gain * coefficients.fetch("conversion_rate")
      conversion_profit = expected_conversion_gain * coefficients.fetch("profit_per_conversion_yen")
      click_profit = expected_click_gain * coefficients.fetch("click_value_yen")
      {
        expected_ctr_gain:,
        expected_click_gain:,
        expected_conversion_gain:,
        expected_revenue_yen: [ conversion_profit, click_profit ].max
      }
    end

    def metric_value(metrics, source, key, fallback:)
      value = metrics.dig(source, key)
      return decimal(value) if value.present?

      assumed_key = "#{source}.#{key}"
      assumed_fields << assumed_key
      assumption_reasons[assumed_key] = "missing_snapshot_metric_fallback"
      input_sources[assumed_key] = "initial_coefficients"
      decimal(fallback)
    end

    def calibrated_success_probability(improvement_type)
      base = decimal(first_present(metadata["success_probability"], candidate.success_probability, 0.55))
      business_stats = business_learning_stats(improvement_type)
      return [ [ business_stats.success_rate, 0.95.to_d ].min, 0.05.to_d ].max if business_stats&.active?

      calibration = calibration_for(improvement_type)
      [ [ base * calibration.probability_factor, 0.95.to_d ].min, 0.05.to_d ].max
    end

    def profit_factor_for(improvement_type)
      business_stats = business_learning_stats(improvement_type)
      return business_stats.profit_factor if business_stats&.active?

      calibration_for(improvement_type).profit_factor
    end

    def calibration_for(improvement_type)
      @calibrations ||= {}
      @calibrations[improvement_type] ||= begin
        specific = ActionPredictionCalibration.for_action_type(calibration_action_type(improvement_type))
        specific.active? ? specific : ActionPredictionCalibration.for_action_type(candidate.action_type.presence || "article_update")
      end
    end

    def calibration_action_type(improvement_type)
      "article_opportunity:#{improvement_type}"
    end

    def model_source_for(improvement_type)
      return "business_learning" if business_learning_stats(improvement_type)&.active?

      calibration = calibration_for(improvement_type)
      return "improvement_type_learning" if calibration.active?

      assumed_fields.any? ? "initial_coefficients" : "business_settings"
    end

    def learning_source_for(improvement_type, model_source)
      return "business:#{candidate.business_id}:#{improvement_type}" if model_source == "business_learning"

      calibration = calibration_for(improvement_type)
      return calibration.action_type if calibration.active?

      model_source
    end

    def confidence_for(model_source)
      case model_source
      when "business_learning"
        0.91.to_d
      when "improvement_type_learning"
        0.72.to_d
      when "business_settings"
        0.65.to_d
      else
        0.34.to_d
      end
    end

    def result_metadata(improvement_type, metrics, coefficients, estimate, expected_revenue, expected_profit, work_cost, success_probability, confidence, source)
      {
        "expected_profit_model" => {
          "name" => MODEL_NAME,
          "value_model" => "grounded_article_opportunity_profit",
          "calibration_version" => CALIBRATION_VERSION,
          "improvement_type" => improvement_type,
          "expected_profit_yen" => expected_profit.to_i,
          "expected_revenue_yen" => expected_revenue.to_i,
          "expected_improvement_score" => decimal(metadata["expected_improvement_score"]).to_f.round(2),
          "expected_ctr_gain" => estimate.fetch(:expected_ctr_gain).to_f.round(4),
          "expected_click_gain" => estimate.fetch(:expected_click_gain).to_f.round(2),
          "expected_conversion_gain" => estimate.fetch(:expected_conversion_gain).to_f.round(4),
          "success_probability" => success_probability.to_f.round(4),
          "work_cost_yen" => work_cost.round.to_i,
          "confidence" => confidence.to_f.round(4),
          "model_source" => source,
          "learning_source" => learning_source_for(improvement_type, source),
          "calibration_update_targets" => calibration_update_targets(improvement_type),
          "input_sources" => input_sources,
          "assumption_used" => assumed_fields.any?,
          "assumed_fields" => assumed_fields.uniq,
          "assumption_reasons" => assumption_reasons,
          "initial_coefficients" => INITIAL_COEFFICIENTS,
          "used_gsc" => metrics["gsc"],
          "used_ga4" => metrics["ga4"],
          "used_shop_click" => metrics["shop_click"],
          "used_learning" => metrics["learning"],
          "rank_improvement_diagnostics" => estimate[:rank_diagnostics]&.deep_stringify_keys,
          "calculation_reason" => calculation_reason(improvement_type, estimate, success_probability, work_cost, source)
        }.compact
      }
    end

    def calibration_update_targets(improvement_type)
      [
        calibration_action_type(improvement_type),
        candidate.action_type.presence || "article_update"
      ].uniq
    end

    def calculation_reason(improvement_type, estimate, success_probability, work_cost, source)
      "#{improvement_type}を、追加クリック#{estimate.fetch(:expected_click_gain).to_f.round(1)}件、追加CV#{estimate.fetch(:expected_conversion_gain).to_f.round(3)}件、成功率#{(success_probability * 100).to_f.round(1)}%、実行コスト#{work_cost.round.to_i}円で推定しました。model_source=#{source}"
    end

    def target_ctr_for(position)
      pos = decimal(position)
      return 0.28.to_d if pos <= 1
      return 0.15.to_d if pos <= 3
      return 0.08.to_d if pos <= 5
      return 0.04.to_d if pos <= 10
      return 0.025.to_d if pos <= 20
      return 0.012.to_d if pos <= 50

      0.005.to_d
    end

    def rank_improvement_ctr_for(position)
      pos = decimal(position)
      return 0.28.to_d if pos <= 1

      curve = [
        [ 1.to_d, 0.28.to_d ],
        [ 3.to_d, 0.15.to_d ],
        [ 5.to_d, 0.08.to_d ],
        [ 10.to_d, 0.04.to_d ],
        [ 20.to_d, 0.018.to_d ],
        [ 50.to_d, 0.006.to_d ]
      ]
      lower, upper = curve.each_cons(2).find { |left, right| pos >= left.first && pos <= right.first }
      return 0.005.to_d unless lower && upper

      progress = (pos - lower.first) / (upper.first - lower.first)
      lower.last + ((upper.last - lower.last) * progress)
    end

    def rank_impression_gain_rate(metrics, position, improved_position)
      learning_rate = first_present(
        metrics.dig("learning", "rank_impression_gain_rate"),
        metrics.dig("learning", "average_rank_impression_gain_rate"),
        metrics.dig("learning", "rank_improvement_impression_gain_rate")
      )
      return normalize_rate(learning_rate) if learning_rate.present?

      business_rate = first_present(
        business_metadata["rank_impression_gain_rate"],
        business_metadata["article_rank_impression_gain_rate"],
        business_metadata["rank_improvement_impression_gain_rate"]
      )
      return normalize_rate(business_rate) if business_rate.present?

      current_visibility = rank_visibility_for(position)
      improved_visibility = rank_visibility_for(improved_position)
      [ (improved_visibility / current_visibility) - 1, 0.to_d ].max
    end

    def rank_visibility_for(position)
      pos = decimal(position)
      return 1.to_d if pos <= 1

      curve = [
        [ 1.to_d, 1.to_d ],
        [ 3.to_d, 0.75.to_d ],
        [ 5.to_d, 0.55.to_d ],
        [ 10.to_d, 0.35.to_d ],
        [ 20.to_d, 0.16.to_d ],
        [ 50.to_d, 0.06.to_d ]
      ]
      lower, upper = curve.each_cons(2).find { |left, right| pos >= left.first && pos <= right.first }
      return 0.02.to_d unless lower && upper

      progress = (pos - lower.first) / (upper.first - lower.first)
      lower.last + ((upper.last - lower.last) * progress)
    end

    BusinessLearningStats = Data.define(:sample_count, :profit_factor, :success_rate) do
      def active?
        sample_count.to_i >= 3
      end
    end

    def business_learning_stats(improvement_type)
      return nil if candidate.business_id.blank?

      @business_learning_stats ||= {}
      @business_learning_stats[improvement_type] ||= begin
        results = ActionResult.evaluated
                              .includes(:action_candidate)
                              .where(business_id: candidate.business_id)
                              .where.not(action_candidate_id: nil)
                              .select { |result| article_opportunity_result?(result, improvement_type) }
        build_business_learning_stats(results)
      end
    end

    def article_opportunity_result?(result, improvement_type)
      related_candidate = result.action_candidate
      return false unless related_candidate

      related_metadata = related_candidate.metadata.to_h
      related_metadata["value_model_name"].to_s == Aicoo::ArticleOpportunityAnalyzer::SnapshotRunner::MODEL_NAME &&
        related_metadata["opportunity_type"].to_s == improvement_type.to_s
    end

    def build_business_learning_stats(results)
      return BusinessLearningStats.new(sample_count: 0, profit_factor: 1.to_d, success_rate: 0.55.to_d) if results.blank?

      actual_values = results.map { |result| decimal(result.actual_profit_yen) }
      predicted_values = results.map { |result| decimal(result.predicted_expected_profit_yen) }.select(&:positive?)
      factor = predicted_values.any? ? safe_factor(actual_values.sum / actual_values.size, predicted_values.sum / predicted_values.size) : 1.to_d
      success_rate = results.count { |result| result.actual_profit_yen.to_i.positive? }.to_d / results.size
      BusinessLearningStats.new(sample_count: results.size, profit_factor: factor, success_rate:)
    end

    def safe_factor(actual, predicted)
      return 1.to_d unless predicted.to_d.positive?

      [ [ actual.to_d / predicted.to_d, ActionPredictionCalibration::MIN_FACTOR ].max, ActionPredictionCalibration::MAX_FACTOR ].min
    end

    def normalize_rate(value)
      rate = decimal(value)
      rate > 1 ? rate / 100 : rate
    end

    def first_present(*values)
      values.find(&:present?)
    end

    def decimal(value)
      return 0.to_d if value.nil?

      value.to_d
    rescue ArgumentError, NoMethodError
      0.to_d
    end
  end
end
