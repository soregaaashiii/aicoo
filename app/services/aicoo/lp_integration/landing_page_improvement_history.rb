module Aicoo
  module LpIntegration
    class LandingPageImprovementHistory
      def initialize(business)
        @business = business
      end

      def call
        candidates.filter_map do |candidate|
          landing_page_id = candidate.metadata.to_h["landing_page_id"].to_i
          next if landing_page_id.zero?

          task = tasks_by_candidate[candidate.id]
          execution = task&.auto_revision_executions&.max_by(&:created_at)
          {
            landing_page_id:,
            occurred_at: execution&.finished_at || task&.finished_at || candidate.created_at,
            change_content: candidate.metadata.to_h["change_content"].presence || candidate.title,
            expected_profit_yen: candidate.final_expected_value_yen.to_i,
            actual_profit_yen: revenue_by_candidate.fetch(candidate.id, 0),
            commit_sha: execution&.commit_sha,
            pull_request_url: execution&.pull_request_url,
            deploy_status: execution&.deploy_status,
            result: execution&.result_summary.presence || task&.result_summary.presence || task&.status.presence || candidate.status
          }
        end.sort_by { |row| row[:occurred_at] || Time.zone.at(0) }.reverse
      end

      private

      attr_reader :business

      def candidates
        @candidates ||= business.action_candidates.where(generation_source: %w[lp_learning manual]).to_a
      end

      def tasks_by_candidate
        @tasks_by_candidate ||= business.auto_revision_tasks.includes(:auto_revision_executions).index_by(&:action_candidate_id)
      end

      def revenue_by_candidate
        @revenue_by_candidate ||= business.revenue_events.where(action_candidate_id: candidates.map(&:id)).group(:action_candidate_id).sum(:amount)
      end
    end
  end
end
