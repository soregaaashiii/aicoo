module Aicoo
  class ActivityActionResultBridge
    Result = Data.define(:status, :action_result, :reason)

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

      track = ActivityLearningTrack.call(evaluation)
      return skipped("independent_activity_without_candidate") unless track.name == "action_candidate"

      candidate = track.action_candidate
      return skipped("candidate_business_mismatch") unless candidate.business_id == activity_log.business_id

      action_result = upsert_action_result(candidate, track:)
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

    def upsert_action_result(candidate, track:)
      action_result = candidate.action_result || candidate.build_action_result
      action_result.assign_attributes(action_result_attributes(candidate, track:))
      action_result.save!
      action_result
    end

    def action_result_attributes(candidate, track:)
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
        metadata: action_result_metadata(candidate, track:)
      }
    end

    def action_result_metadata(candidate, track:)
      candidate.action_result&.metadata.to_h.merge(
        "learning_track" => "action_candidate",
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
          "candidate_link_source" => track.link_source,
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
