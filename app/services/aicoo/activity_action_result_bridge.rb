module Aicoo
  class ActivityActionResultBridge
    Result = Data.define(:status, :action_result, :reason)

    TERMINAL_CANDIDATE_STATUSES = %w[
      archived
      rejected
      done
      canceled
      cancelled
      invalid
      resolved
      superseded
      rejected_duplicate
      rejected_irrelevant
    ].freeze

    CANDIDATE_ID_KEYS = %w[
      action_candidate_id
      candidate_id
    ].freeze

    def self.call(evaluation)
      new(evaluation).call
    end

    def initialize(evaluation)
      @evaluation = evaluation
      @activity_log = evaluation&.business_activity_log
    end

    def call
      return skipped("evaluation_not_evaluated") unless evaluation&.evaluated?
      return skipped("activity_log_missing") unless activity_log

      candidate = resolve_candidate
      return skipped("action_candidate_not_found") unless candidate
      return skipped("candidate_business_mismatch") unless candidate.business_id == activity_log.business_id

      action_result = upsert_action_result(candidate)
      refresh_learning(action_result)
      mark_bridge!("generated", action_result:, reason: nil)
      Result.new(status: "generated", action_result:, reason: nil)
    rescue StandardError => e
      Rails.logger.warn(
        "[ActivityLearningPipeline] action_result_bridge_failed " \
        "activity_evaluation_id=#{evaluation&.id} activity_log_id=#{activity_log&.id} " \
        "error=#{e.class}: #{e.message}"
      )
      mark_bridge!("failed", action_result: nil, reason: "#{e.class}: #{e.message}") if evaluation&.persisted?
      Result.new(status: "failed", action_result: nil, reason: "#{e.class}: #{e.message}")
    end

    private

    attr_reader :evaluation, :activity_log

    def skipped(reason)
      mark_bridge!("skipped", action_result: nil, reason:) if evaluation&.persisted?
      Result.new(status: "skipped", action_result: nil, reason:)
    end

    def resolve_candidate
      candidate_from_explicit_id ||
        candidate_from_execution_log ||
        candidate_from_resource_reference
    end

    def candidate_from_explicit_id
      explicit_candidate_ids.each do |id|
        candidate = ActionCandidate.find_by(id:)
        return candidate if candidate
      end
      nil
    end

    def explicit_candidate_ids
      payloads = [
        activity_log.metadata,
        activity_log.before_snapshot,
        activity_log.after_snapshot,
        evaluation.metadata
      ].map { |payload| payload.to_h.deep_stringify_keys }

      payloads.flat_map do |payload|
        nested_candidate = payload["action_candidate"].is_a?(Hash) ? payload["action_candidate"] : {}
        CANDIDATE_ID_KEYS.filter_map { |key| payload[key].presence } +
          CANDIDATE_ID_KEYS.filter_map { |key| nested_candidate[key].presence }
      end.uniq.select { |id| numeric_id?(id) }
    end

    def candidate_from_execution_log
      log_id = [
        activity_log.metadata.to_h["action_execution_log_id"],
        activity_log.after_snapshot.to_h["action_execution_log_id"],
        evaluation.metadata.to_h.dig("activity_learning_pipeline", "action_execution_log_id")
      ].find { |id| numeric_id?(id) }
      return unless log_id

      ActionExecutionLog.find_by(id: log_id)&.action_candidate
    end

    def candidate_from_resource_reference
      resource_id = activity_log.resource_id.to_s
      return if resource_id.blank? || resource_id == "unknown"

      key_fragment = resource_key_fragment
      return unless key_fragment

      ActionCandidate
        .where(business_id: activity_log.business_id)
        .order(updated_at: :desc, id: :desc)
        .limit(500)
        .detect do |candidate|
          !candidate.status.to_s.in?(TERMINAL_CANDIDATE_STATUSES) &&
            metadata_references_resource?(candidate.metadata.to_h, key_fragment, resource_id)
        end
    end

    def resource_key_fragment
      case activity_log.resource_type.to_s
      when "Article"
        "article"
      when "Shop"
        "shop"
      end
    end

    def metadata_references_resource?(payload, key_fragment, resource_id)
      each_metadata_pair(payload) do |key, value|
        next unless key.to_s.include?(key_fragment) || key.to_s.in?(%w[resource_id target_record_id])

        return true if value.to_s == resource_id
      end
      false
    end

    def numeric_id?(value)
      value.to_s.match?(/\A\d+\z/)
    end

    def each_metadata_pair(value, &block)
      case value
      when Hash
        value.each do |key, child|
          yield key.to_s, child
          each_metadata_pair(child, &block)
        end
      when Array
        value.each { |child| each_metadata_pair(child, &block) }
      end
    end

    def upsert_action_result(candidate)
      action_result = candidate.action_result || candidate.build_action_result
      action_result.assign_attributes(action_result_attributes(candidate))
      action_result.save!
      action_result
    end

    def action_result_attributes(candidate)
      {
        business: candidate.business,
        executed_on: activity_log.occurred_at.to_date,
        evaluated_on: (evaluation.evaluated_at || Time.current).to_date,
        evaluation_status: "evaluated",
        actual_revenue_yen: delta_integer("revenue_yen"),
        actual_profit_yen: delta_integer("revenue_yen"),
        actual_impressions_delta: delta_integer("impressions"),
        actual_clicks_delta: delta_integer("clicks"),
        actual_sessions_delta: delta_integer("sessions"),
        actual_pageviews_delta: delta_integer("pageviews"),
        actual_phone_clicks_delta: delta_integer("phone_clicks"),
        actual_map_clicks_delta: delta_integer("map_clicks"),
        actual_affiliate_clicks_delta: delta_integer("affiliate_clicks"),
        metadata: action_result_metadata(candidate)
      }
    end

    def action_result_metadata(candidate)
      candidate.action_result&.metadata.to_h.merge(
        "activity_learning_pipeline" => {
          "auto_generated" => true,
          "source" => "business_activity_log",
          "business_activity_log_id" => activity_log.id,
          "activity_evaluation_id" => evaluation.id,
          "evaluation_window_days" => evaluation.evaluation_window_days,
          "activity_type" => activity_log.activity_type,
          "source_app" => activity_log.source_app,
          "resource_type" => activity_log.resource_type,
          "resource_id" => activity_log.resource_id,
          "metric_deltas" => evaluation.metric_deltas,
          "baseline_snapshot" => evaluation.baseline_snapshot,
          "result_snapshot" => evaluation.result_snapshot,
          "generated_at" => Time.current.iso8601
        }
      )
    end

    def delta_integer(metric)
      value = evaluation.metric_deltas.to_h.dig(metric, "delta")
      return 0 if value.blank?

      value.to_d.round.to_i
    end

    def refresh_learning(action_result)
      Aicoo::ExpectedValueLearningRefresh.refresh_after_action_result!(
        action_result,
        source: "activity_learning_pipeline"
      )
    end

    def mark_bridge!(status, action_result:, reason:)
      evaluation.update!(
        metadata: evaluation.metadata.to_h.merge(
          "action_result_bridge" => {
            "status" => status,
            "reason" => reason,
            "action_result_id" => action_result&.id,
            "checked_at" => Time.current.iso8601
          }
        )
      )
    end
  end
end
