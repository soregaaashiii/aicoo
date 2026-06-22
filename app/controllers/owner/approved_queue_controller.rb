module Owner
  class ApprovedQueueController < ApplicationController
    def index
      @sort = params[:sort].presence_in(%w[approved_at expected_total_value]) || "approved_at"
      @approved_candidates = approved_candidates
    end

    def queue_selected
      result = AicooExecutor::ApprovedCandidateQueuer.queue_selected!(params[:action_candidate_ids].to_a)

      redirect_to owner_approved_queue_path, notice: queue_message(result)
    end

    def queue_all
      result = AicooExecutor::ApprovedCandidateQueuer.queue_all!

      redirect_to owner_approved_queue_path, notice: queue_message(result)
    end

    private

    def approved_candidates
      scope = ActionCandidate.includes(:business).where(status: "approved")
      case @sort
      when "expected_total_value"
        scope.order(expected_total_value_yen: :desc, approved_at: :desc)
      else
        scope.order(approved_at: :desc, expected_total_value_yen: :desc)
      end
    end

    def queue_message(result)
      reasons = result.skipped_reasons.map { |reason, count| "#{reason}: #{count}件" }.join(" / ")
      [
        "送信対象 #{result.target_count}件",
        "作成 #{result.created_count}件",
        "スキップ #{result.skipped_count}件",
        reasons.presence
      ].compact.join("、")
    end
  end
end
