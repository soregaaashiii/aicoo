module Aicoo
  module LpIntegration
    class LandingPageImprovementHistory
      def initialize(business, candidates: nil, tasks: nil, revenue_events: nil)
        @business = business
        @provided_candidates = candidates
        @provided_tasks = tasks
        @provided_revenue_events = revenue_events
      end

      def call
        candidates.filter_map do |candidate|
          landing_page_id = candidate.metadata.to_h["landing_page_id"].to_i
          next if landing_page_id.zero?

          task = tasks_by_candidate[candidate.id]
          execution = task&.auto_revision_executions&.max_by(&:created_at)
          {
            action_candidate_id: candidate.id,
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

      attr_reader :business, :provided_candidates, :provided_tasks, :provided_revenue_events

      def candidates
        @candidates ||= if provided_candidates
          Array(provided_candidates).select { |candidate| candidate.generation_source.in?(%w[lp_learning manual]) }
        else
          business.action_candidates.where(generation_source: %w[lp_learning manual]).to_a
        end
      end

      def tasks_by_candidate
        @tasks_by_candidate ||= (provided_tasks || business.auto_revision_tasks.includes(:auto_revision_executions)).index_by(&:action_candidate_id)
      end

      def revenue_by_candidate
        @revenue_by_candidate ||= if provided_revenue_events
          candidate_ids = candidates.map(&:id).to_set
          Array(provided_revenue_events)
            .select { |event| candidate_ids.include?(event.action_candidate_id) }
            .group_by(&:action_candidate_id)
            .transform_values { |events| events.sum(&:amount) }
        else
          business.revenue_events.where(action_candidate_id: candidates.map(&:id)).group(:action_candidate_id).sum(:amount)
        end
      end
    end
  end
end
