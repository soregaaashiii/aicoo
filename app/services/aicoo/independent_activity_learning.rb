require "digest"

module Aicoo
  class IndependentActivityLearning
    BURST_WINDOW = 1.hour
    MAX_CONFIDENCE = 0.9

    def self.record!(evaluation)
      new(evaluation).record!
    end

    def initialize(evaluation)
      @evaluation = evaluation
      @activity_log = evaluation.business_activity_log
    end

    def record!
      track = ActivityLearningTrack.call(evaluation)
      return if track.name == "action_candidate"

      evaluation.update!(metadata: evaluation.metadata.to_h.merge(
        "learning_track" => "independent_activity",
        "independent_activity_learning" => attributes
      ))
      evaluation
    end

    def attributes
      learning_metadata
    end

    private

    attr_reader :evaluation, :activity_log

    def learning_metadata
      dimensions = activity_dimensions(activity_log)
      logs = grouped_logs(dimensions)
      log_ids = logs.map(&:id)
      activity_types = overlapping_activity_types
      {
        "action_candidate_id" => nil,
        "activity_type" => activity_log.activity_type,
        "business_id" => activity_log.business_id,
        "area" => dimensions["area"],
        "station" => dimensions["station"],
        "genre" => dimensions["genre"],
        "smoking_type" => dimensions["smoking_type"],
        "shop_count" => resource_count(logs, "Shop"),
        "article_count" => resource_count(logs, "Article"),
        "created_count" => logs.count { |log| created_activity?(log.activity_type) },
        "updated_count" => logs.count { |log| updated_activity?(log.activity_type) },
        "source" => activity_log.source_app,
        "source_method" => activity_log.source_method,
        "manual_activity" => true,
        "group_key" => group_key(dimensions),
        "representative_activity_log_id" => log_ids.min,
        "grouped_activity_log_ids" => log_ids,
        "evaluation_window_days" => evaluation.evaluation_window_days,
        "learning_status" => evaluation.status,
        "confidence" => confidence(dimensions, activity_types),
        "concurrent_activity_types" => activity_types,
        "outcome" => outcome,
        "roi" => roi(logs),
        "recorded_at" => Time.current.iso8601
      }
    end

    def grouped_logs(dimensions)
      BusinessActivityLog
        .where(
          business_id: activity_log.business_id,
          source_app: activity_log.source_app,
          activity_type: activity_log.activity_type,
          occurred_at: burst_range
        )
        .to_a
        .select do |log|
          activity_dimensions(log).slice("area", "station", "genre", "smoking_type") ==
            dimensions.slice("area", "station", "genre", "smoking_type")
        end
    end

    def overlapping_activity_types
      BusinessActivityLog
        .where(business_id: activity_log.business_id, occurred_at: burst_range)
        .distinct
        .pluck(:activity_type)
        .sort
    end

    def burst_range
      start_at = activity_log.occurred_at.beginning_of_hour
      start_at...(start_at + BURST_WINDOW)
    end

    def activity_dimensions(log)
      payloads = [ log.metadata, log.after_snapshot, log.before_snapshot ].map { |value| value.to_h.deep_stringify_keys }
      {
        "area" => first_value(payloads, %w[area area_name city district]),
        "station" => first_value(payloads, %w[station station_name nearest_station]),
        "genre" => first_value(payloads, %w[genre genre_name category category_name]),
        "smoking_type" => first_value(payloads, %w[smoking_type smoking_status smoking_area])
      }
    end

    def first_value(payloads, keys)
      payloads.each do |payload|
        value = deep_value(payload, keys)
        return value if value.present?
      end
      nil
    end

    def deep_value(value, keys)
      case value
      when Hash
        value.each do |key, child|
          return child if key.to_s.in?(keys) && child.present?

          nested = deep_value(child, keys)
          return nested if nested.present?
        end
      when Array
        value.each do |child|
          nested = deep_value(child, keys)
          return nested if nested.present?
        end
      end
      nil
    end

    def resource_count(logs, resource_type)
      logs.select { |log| log.resource_type == resource_type }.map(&:resource_id).reject(&:blank?).uniq.size
    end

    def created_activity?(activity_type)
      activity_type.to_s.match?(/(?:created|added)\z/)
    end

    def updated_activity?(activity_type)
      activity_type.to_s.match?(/(?:updated|improvement|changed|addition)\z/)
    end

    def group_key(dimensions)
      Digest::SHA256.hexdigest([
        activity_log.business_id,
        activity_log.source_app,
        activity_log.activity_type,
        dimensions["area"],
        dimensions["station"],
        dimensions["genre"],
        dimensions["smoking_type"],
        activity_log.occurred_at.beginning_of_hour.iso8601
      ].join(":"))
    end

    def confidence(dimensions, activity_types)
      repeat_count = prior_matching_learning_count(dimensions)
      value = 0.3 + ([ repeat_count, 5 ].min * 0.1)
      value -= 0.15 if activity_types.size > 1
      value.clamp(0.1, MAX_CONFIDENCE).round(2)
    end

    def prior_matching_learning_count(dimensions)
      current_group_key = group_key(dimensions)
      ActivityEvaluation
        .where(business_id: activity_log.business_id, status: "evaluated")
        .where.not(id: evaluation.id)
        .order(id: :desc)
        .limit(1_000)
        .filter_map do |other|
          learning = other.metadata.to_h["independent_activity_learning"].to_h
          next unless learning["activity_type"] == activity_log.activity_type
          next unless learning.slice("area", "station", "genre", "smoking_type") == dimensions.slice("area", "station", "genre", "smoking_type")
          next if learning["group_key"] == current_group_key

          learning["group_key"]
        end.uniq.size
    end

    def outcome
      {
        "metrics" => evaluation.metric_deltas.to_h,
        "baseline" => evaluation.baseline_snapshot.to_h,
        "result" => evaluation.result_snapshot.to_h
      }
    end

    def roi(logs)
      work_seconds = logs.sum { |log| log.estimated_work_seconds.to_i }
      return if work_seconds.zero?

      revenue_delta = evaluation.metric_deltas.to_h.dig("revenue_yen", "delta").to_f
      hourly_cost = AicooLabSetting.first&.hourly_cost_yen.to_f
      work_cost = work_seconds / 3600.0 * hourly_cost
      return if work_cost.zero?

      (revenue_delta / work_cost).round(3)
    end
  end
end
