module Aicoo
  class OpportunityProgressUpdater
    def self.call(action_candidate)
      new(action_candidate).call
    end

    def initialize(action_candidate)
      @action_candidate = action_candidate
    end

    def call
      opportunity = opportunity_for(action_candidate)
      return unless opportunity

      related = related_candidates(opportunity)
      progress_status = progress_status_for(related)
      opportunity.update_columns(
        status: status_for(progress_status),
        metadata: opportunity.metadata.to_h.merge(
          "progress_status" => progress_status,
          "completed_action_candidate_ids" => related.select(&:executed?).map(&:id),
          "pending_action_candidate_ids" => related.reject(&:executed?).map(&:id),
          "progress_updated_at" => Time.current.iso8601
        ),
        updated_at: Time.current
      )
      unblock_ready_candidates!(related)
      opportunity
    end

    private

    attr_reader :action_candidate

    def opportunity_for(candidate)
      opportunity_id = candidate.metadata.to_h["opportunity_id"]
      return OpportunityDiscoveryItem.find_by(id: opportunity_id) if opportunity_id.present?

      candidate.opportunity_discovery_items.order(updated_at: :desc).first
    end

    def related_candidates(opportunity)
      ids = Array(opportunity.metadata.to_h["related_action_candidate_ids"]).map(&:to_i)
      ids |= [ opportunity.action_candidate_id ].compact
      ids |= ActionCandidate.where("metadata ->> 'opportunity_id' = ?", opportunity.id.to_s).pluck(:id)
      ActionCandidate.where(id: ids.uniq).active_for_ranking.to_a
    end

    def progress_status_for(related)
      return "未対応" if related.empty?
      return "解決済み" if related.all?(&:executed?)
      return "一部対応" if related.any?(&:executed?)

      "未対応"
    end

    def status_for(progress_status)
      case progress_status
      when "解決済み" then "reviewed"
      when "一部対応" then "converted"
      else "pending"
      end
    end

    def unblock_ready_candidates!(related)
      related.each do |candidate|
        metadata = candidate.metadata.to_h
        prerequisite_id = metadata["prerequisite_action_candidate_id"]
        next if prerequisite_id.blank?
        next unless ActionCandidate.find_by(id: prerequisite_id)&.executed?

        candidate.update_columns(
          metadata: metadata.except("blocked", "blocked_reason", "prerequisite_action_candidate_id").merge(
            "unblocked_at" => Time.current.iso8601,
            "unblocked_by" => action_candidate.id
          ),
          updated_at: Time.current
        )
      end
    end
  end
end
