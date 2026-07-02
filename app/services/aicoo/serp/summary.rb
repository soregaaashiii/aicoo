module Aicoo
  module Serp
    class Summary
      Result = Data.define(
        :health,
        :business_count,
        :active_keyword_count,
        :today_scan_count,
        :success_count,
        :warning_count,
        :fail_count,
        :failed_business_count,
        :stopped_business_count,
        :pending_keyword_count,
        :today_serp_action_candidate_count,
        :today_query_count,
        :today_success_query_count,
        :today_failed_query_count,
        :top_priority_business,
        :inactive_candidate_count,
        :last_executed_at,
        :scheduler_enabled,
        :latest_run,
        :next_scheduled_at
      )

      def self.call
        new.call
      end

      def call
        Result.new(
          health:,
          business_count: businesses.count,
          active_keyword_count: BusinessSerpKeyword.active.count,
          today_scan_count: today_analyses.count,
          success_count: today_analyses.successful.count,
          warning_count: today_warning_count,
          fail_count: today_analyses.failed.count,
          failed_business_count: today_analyses.failed.select(:business_id).distinct.count,
          stopped_business_count: stopped_businesses.count,
          pending_keyword_count: BusinessSerpKeyword.pending.count,
          today_serp_action_candidate_count: today_serp_candidates.count,
          today_query_count: today_query_count,
          today_success_query_count: today_success_query_count,
          today_failed_query_count: today_failed_query_count,
          top_priority_business:,
          inactive_candidate_count:,
          last_executed_at:,
          scheduler_enabled: Aicoo::Serp::Scheduler.enabled?,
          latest_run:,
          next_scheduled_at:
        )
      end

      private

      def businesses
        @businesses ||= Business.real_businesses
      end

      def today_analyses
        @today_analyses ||= SerpAnalysis.where(analyzed_at: Time.zone.today.all_day)
      end

      def today_serp_candidates
        @today_serp_candidates ||= ActionCandidate.where(generation_source: "serp", created_at: Time.zone.today.all_day)
      end

      def stopped_businesses
        @stopped_businesses ||= businesses.select do |business|
          !business.serp_enabled? ||
            (business.business_serp_keywords.active.count.zero? && business.business_serp_keywords.pending.count.positive?)
        end
      end

      def inactive_candidate_count
        BusinessSerpKeyword.where(status: %w[active paused]).to_a.count do |keyword|
          keyword.metadata_json.to_h["inactive_candidate"] == true
        end
      end

      def today_warning_count
        AicooDailyRunStep
          .where(step_name: Aicoo::Serp::OptionalMode::SERP_DEPENDENT_STEPS, created_at: Time.zone.today.all_day)
          .to_a.count { |step| step.status == "skipped" || step.metadata.to_h["warning"] == true }
      end

      def today_query_ids
        @today_query_ids ||= today_analyses.filter_map { |analysis| analysis.raw_summary.to_h["serp_query_id"] }.uniq
      end

      def today_query_count
        latest_run&.query_count.to_i.positive? ? latest_run.query_count : today_query_ids.size
      end

      def today_success_query_count
        latest_run&.success_count.to_i.positive? ? latest_run.success_count : today_analyses.successful.filter_map { |analysis| analysis.raw_summary.to_h["serp_query_id"] }.uniq.size
      end

      def today_failed_query_count
        latest_run&.failure_count.to_i.positive? ? latest_run.failure_count : today_analyses.failed.filter_map { |analysis| analysis.raw_summary.to_h["serp_query_id"] }.uniq.size
      end

      def top_priority_business
        query = SerpQuery.enabled.includes(:business).order(:priority, updated_at: :desc).first
        return query.business if query

        keyword = BusinessSerpKeyword.active.includes(:business).order(priority_score: :desc, updated_at: :desc).first
        keyword&.business
      end

      def last_executed_at
        latest_run&.started_at || SerpAnalysis.maximum(:analyzed_at)
      end

      def latest_run
        @latest_run ||= SerpRun.recent.first
      end

      def next_scheduled_at
        settings = Aicoo::Serp::Scheduler.settings
        return nil unless ActiveModel::Type::Boolean.new.cast(settings["scheduler_enabled"])

        hour, min = settings["run_time"].to_s.split(":").map(&:to_i)
        today = Time.zone.today
        scheduled = Time.zone.local(today.year, today.month, today.day, hour || 7, min || 0)
        scheduled.future? ? scheduled : scheduled + 1.day
      end

      def health
        return "Broken" if latest_run&.status == "failed"
        return "Warning" if latest_run&.status == "partial_failed"
        return "Broken" if today_analyses.failed.exists?
        return "Warning" if stopped_businesses.any? || BusinessSerpKeyword.pending.exists?

        "Healthy"
      end
    end
  end
end
