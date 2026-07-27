module Aicoo
  module LpIntegration
    class LandingPageLearningBuilder
      EVALUATION_DAYS = 7
      COMPLETED_TASK_STATUSES = %w[completed succeeded partial_succeeded].freeze

      def initialize(business:, landing_page:, snapshots:, activity_logs: nil, revenue_events: nil)
        @business = business
        @landing_page = landing_page
        @snapshots = snapshots
        @activity_logs = activity_logs
        @revenue_events = revenue_events
      end

      def call
        task = completed_improvement_task
        return unless task

        evaluation_started_at = publication_or_completion_time(task)
        return pending_learning(task, evaluation_started_at, "publication_time_missing") unless evaluation_started_at

        elapsed_days = [ (Time.current.to_date - evaluation_started_at.to_date).to_i, 0 ].max
        return pending_learning(task, evaluation_started_at, "collecting_7_day_result", elapsed_days:) if elapsed_days < EVALUATION_DAYS

        source_page = source_landing_page(task)
        before = measurement_for(
          source_page,
          started_at: evaluation_started_at - EVALUATION_DAYS.days,
          ended_at: evaluation_started_at - 1.second
        )
        after = measurement_for(
          landing_page,
          started_at: evaluation_started_at,
          ended_at: [ evaluation_started_at + EVALUATION_DAYS.days, Time.current ].min
        )
        deltas = metric_deltas(before, after)
        success = successful?(task.action_candidate, deltas)

        {
          "status" => "evaluated",
          "improvement_type" => improvement_type(task.action_candidate),
          "action_candidate_id" => task.action_candidate_id,
          "auto_revision_task_id" => task.id,
          "source_landing_page_id" => source_page.id,
          "landing_page_id" => landing_page.id,
          "evaluation_window_days" => EVALUATION_DAYS,
          "evaluation_started_at" => evaluation_started_at.iso8601,
          "evaluated_at" => Time.current.iso8601,
          "before" => before,
          "after" => after,
          "deltas" => deltas,
          "profit_delta_yen" => deltas.dig("profit_yen", "delta").to_i,
          "success" => success,
          "confidence" => confidence(before, after),
          "learning_scope" => %w[business global],
          "future_consumer" => "mvp_planner"
        }
      end

      private

      attr_reader :business, :landing_page, :snapshots, :activity_logs, :revenue_events

      def completed_improvement_task
        business.auto_revision_tasks.includes(:action_candidate).where(status: COMPLETED_TASK_STATUSES).to_a
          .select { |task| task.metadata.to_h["workflow_type"] == "external_lp_improvement" }
          .select { |task| task.metadata.to_h["landing_page_prototype_id"].to_i == landing_page.id }
          .max_by { |task| task.finished_at || task.updated_at }
      end

      def source_landing_page(task)
        source_id = task.metadata.to_h["source_landing_page_prototype_id"].to_i
        business.business_prototypes.find_by(id: source_id) || landing_page
      end

      def publication_or_completion_time(task)
        landing_page.landing_page_last_published_at || task.finished_at || task.updated_at
      end

      def pending_learning(task, evaluation_started_at, reason, elapsed_days: 0)
        {
          "status" => "collecting",
          "reason" => reason,
          "improvement_type" => improvement_type(task.action_candidate),
          "action_candidate_id" => task.action_candidate_id,
          "auto_revision_task_id" => task.id,
          "landing_page_id" => landing_page.id,
          "evaluation_window_days" => EVALUATION_DAYS,
          "elapsed_days" => elapsed_days,
          "evaluation_started_at" => evaluation_started_at&.iso8601,
          "confidence" => 0.1
        }.compact
      end

      def measurement_for(page, started_at:, ended_at:)
        analytics = Aicoo::Lovable::LandingPageAnalyticsReader.new(
          business:,
          started_at:,
          ended_at:,
          target_paths: [ page.landing_page_url, page.landing_page_cloudflare_url, page.landing_page_ga4_path ],
          snapshots:
        ).call
        activity = LandingPageActivityReader.new(
          business:,
          landing_page: page,
          started_at:,
          ended_at:,
          activity_logs:,
          revenue_events:
        ).call
        sessions = analytics.ga4["sessions"].to_i
        {
          "sessions" => sessions,
          "users" => analytics.ga4["active_users"].to_i,
          "conversions" => analytics.ga4["conversions"].to_i,
          "conversion_rate" => sessions.positive? ? (analytics.ga4["conversions"].to_d / sessions).round(6).to_f : nil,
          "engagement_seconds" => analytics.ga4["engagement_seconds"],
          "bounce_rate" => analytics.ga4["bounce_rate"],
          "scroll_rate" => analytics.ga4["scroll_rate"],
          "impressions" => analytics.gsc["impressions"].to_i,
          "clicks" => analytics.gsc["clicks"].to_i,
          "ctr" => analytics.gsc["ctr"],
          "average_position" => analytics.gsc["average_position"],
          "inquiries" => activity.inquiries,
          "deals" => activity.deals,
          "contracts" => activity.contracts,
          "revenue_yen" => activity.revenue_yen,
          "profit_yen" => activity.profit_yen
        }
      end

      def metric_deltas(before, after)
        (before.keys | after.keys).to_h do |key|
          before_value = before[key]
          after_value = after[key]
          delta = if before_value.nil? || after_value.nil?
            nil
          else
            (BigDecimal(after_value.to_s) - BigDecimal(before_value.to_s)).round(6).to_f
          end
          [ key, { "before" => before_value, "after" => after_value, "delta" => delta } ]
        end
      end

      def successful?(candidate, deltas)
        profit_delta = deltas.dig("profit_yen", "delta")
        return profit_delta.positive? unless profit_delta.nil? || profit_delta.zero?

        target_metric = candidate.metadata.to_h.dig("lp_expected_value", "target_metric")
        target_metric = "conversion_rate" if target_metric.blank?
        delta = deltas.dig(target_metric, "delta")
        return false if delta.nil?

        target_metric.in?(%w[bounce_rate average_position]) ? delta.negative? : delta.positive?
      end

      def improvement_type(candidate)
        candidate.metadata.to_h.dig("lp_expected_value", "type").presence || candidate.action_type
      end

      def confidence(before, after)
        sample = [ before["sessions"].to_i, after["sessions"].to_i ].min
        sources = 0
        sources += 1 if before["sessions"].to_i.positive? && after["sessions"].to_i.positive?
        sources += 1 if before["impressions"].to_i.positive? && after["impressions"].to_i.positive?
        sources += 1 if before["inquiries"].to_i.positive? || after["inquiries"].to_i.positive?
        sources += 1 if before["profit_yen"].to_i.nonzero? || after["profit_yen"].to_i.nonzero?
        (0.25 + ([ sample, 200 ].min.fdiv(200) * 0.35) + (sources * 0.1)).round(2).clamp(0.25, 0.95)
      end
    end
  end
end
