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
        :top_priority_business,
        :inactive_candidate_count,
        :last_executed_at
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
          top_priority_business:,
          inactive_candidate_count:,
          last_executed_at:
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

      def top_priority_business
        keyword = BusinessSerpKeyword.active.includes(:business).order(priority_score: :desc, updated_at: :desc).first
        keyword&.business
      end

      def last_executed_at
        [
          SerpAnalysis.maximum(:analyzed_at),
          AicooDailyRunStep.where(step_name: Aicoo::Serp::OptionalMode::SERP_DEPENDENT_STEPS).maximum(:created_at)
        ].compact.max
      end

      def health
        return "Broken" if today_analyses.failed.exists?
        return "Warning" if stopped_businesses.any? || BusinessSerpKeyword.pending.exists?

        "Healthy"
      end
    end
  end
end
