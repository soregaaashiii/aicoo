module AicooJudge
  class ActionResultJudge
    Summary = Data.define(
      :label,
      :evaluated_count,
      :average_predicted_expected_profit_yen,
      :average_actual_profit_yen,
      :average_prediction_error_yen,
      :average_prediction_error_rate,
      :hit_rate,
      :big_miss_count,
      :skipped_count
    )
    Result = Data.define(
      :overall_summary,
      :generation_source_summaries,
      :business_summaries,
      :action_type_summaries,
      :metric_rule_summaries,
      :status_summaries,
      :recent_big_misses,
      :recent_hits
    )

    def initialize(filters = {})
      @filters = filters
    end

    def call
      Result.new(
        overall_summary: summary_for("全体", records),
        generation_source_summaries: grouped_summaries(:generation_source),
        business_summaries: grouped_summaries(:business_name),
        action_type_summaries: grouped_summaries(:action_type),
        metric_rule_summaries: grouped_summaries(:metric_rule),
        status_summaries: grouped_summaries(:evaluation_status),
        recent_big_misses: evaluated_records.select { |record| big_miss?(record) }.first(10),
        recent_hits: evaluated_records.select { |record| hit?(record) }.first(10)
      )
    end

    def precision_for(action_candidate)
      {
        generation_source: summary_for(action_candidate.generation_source, records_for(generation_source: action_candidate.generation_source)),
        action_type: summary_for(action_candidate.action_type, records_for(action_type: action_candidate.action_type)),
        business: summary_for(action_candidate.business.name, records_for(business_id: action_candidate.business_id))
      }
    end

    private

    attr_reader :filters

    def grouped_summaries(axis)
      records.group_by { |record| axis_value(record, axis) }
             .sort_by { |label, _group_records| label.to_s }
             .map { |label, group_records| summary_for(label.presence || "未設定", group_records) }
    end

    def summary_for(label, group_records)
      evaluated = group_records.select { |record| record.evaluation_status == "evaluated" }
      skipped_count = group_records.count { |record| record.evaluation_status == "skipped" }
      hit_count = evaluated.count { |record| hit?(record) }

      Summary.new(
        label:,
        evaluated_count: evaluated.count,
        average_predicted_expected_profit_yen: average(evaluated.map(&:predicted_expected_profit_yen)),
        average_actual_profit_yen: average(evaluated.map(&:actual_profit_yen)),
        average_prediction_error_yen: average(evaluated.map(&:prediction_error_yen)),
        average_prediction_error_rate: average(evaluated.map(&:prediction_error_rate)),
        hit_rate: evaluated.any? ? hit_count.to_d / evaluated.count : nil,
        big_miss_count: evaluated.count { |record| big_miss?(record) },
        skipped_count:
      )
    end

    def records_for(criteria)
      records.select do |record|
        criteria.all? { |key, value| axis_value(record, key) == value }
      end
    end

    def records
      @records ||= filtered_scope.to_a
    end

    def evaluated_records
      @evaluated_records ||= records.select { |record| record.evaluation_status == "evaluated" }
                                    .sort_by(&:updated_at)
                                    .reverse
    end

    def filtered_scope
      scope = ActionResult.includes(:business, :action_candidate).order(updated_at: :desc)
      scope = scope.where(business_id: filters[:business_id]) if filters[:business_id].present?
      scope = scope.joins(:action_candidate).where(action_candidates: { generation_source: filters[:generation_source] }) if filters[:generation_source].present?
      scope = scope.joins(:action_candidate).where(action_candidates: { action_type: filters[:action_type] }) if filters[:action_type].present?
      scope = scope.where(evaluated_on: parse_filter_date(filters[:start_date])..) if filters[:start_date].present?
      scope = scope.where(evaluated_on: ..parse_filter_date(filters[:end_date])) if filters[:end_date].present?
      scope
    rescue Date::Error
      ActionResult.none
    end

    def parse_filter_date(value)
      value.respond_to?(:to_date) ? value.to_date : Date.parse(value)
    end

    def axis_value(record, axis)
      case axis
      when :generation_source
        record.action_candidate.generation_source
      when :business_name
        record.business.name
      when :business_id
        record.business_id
      when :action_type
        record.action_candidate.action_type
      when :metric_rule
        metric_rule(record.action_candidate)
      when :evaluation_status
        record.evaluation_status
      end
    end

    def metric_rule(action_candidate)
      action_candidate.metadata.to_h["metric_rule"].presence ||
        action_candidate.evaluation_reason.to_s[/metric_rule:([a-z0-9_]+)/, 1] ||
        "none"
    end

    def hit?(record)
      sign_matches?(record) || record.prediction_error_rate.to_d <= 0.5
    end

    def big_miss?(record)
      record.prediction_error_rate.to_d >= 2 ||
        (record.predicted_expected_profit_yen.to_i.positive? && record.actual_profit_yen.to_i < -record.predicted_expected_profit_yen.to_i.abs)
    end

    def sign_matches?(record)
      predicted = record.predicted_expected_profit_yen.to_i
      actual = record.actual_profit_yen.to_i
      return true if predicted.zero? && actual.zero?

      predicted.positive? == actual.positive?
    end

    def average(values)
      numeric_values = values.compact.map(&:to_d)
      return nil if numeric_values.empty?

      numeric_values.sum / numeric_values.size
    end
  end
end
