module Aicoo
  class ApprovedNewBusinessCandidateRepairer
    Result = Data.define(:checked_count, :repaired_count, :skipped_count, :failed_count, :errors)

    def self.call(...)
      new(...).call
    end

    def initialize(limit: 100, source: "approved_new_business_candidate_repairer")
      @limit = limit
      @source = source
    end

    def call
      checked_count = 0
      repaired_count = 0
      skipped_count = 0
      failed_count = 0
      errors = []

      scope.limit(limit).find_each do |candidate|
        checked_count += 1

        if already_promoted?(candidate)
          skipped_count += 1
          next
        end

        result = ApprovalService.approve(candidate, operator: "system", source:)
        candidate.reload

        if candidate.metadata.to_h.dig("business_promotion", "promoted")
          repaired_count += 1
          Rails.logger.info(
            "[ApprovedNewBusinessCandidateRepairer] repaired action_candidate_id=#{candidate.id} " \
              "business_id=#{candidate.business_id} message=#{result.message}"
          )
        else
          skipped_count += 1
        end
      rescue StandardError => e
        failed_count += 1
        errors << { action_candidate_id: candidate.id, error_class: e.class.name, message: e.message }
        Rails.logger.warn(
          "[ApprovedNewBusinessCandidateRepairer] failed action_candidate_id=#{candidate.id} #{e.class}: #{e.message}"
        )
      end

      Result.new(checked_count:, repaired_count:, skipped_count:, failed_count:, errors:)
    end

    private

    attr_reader :limit, :source

    def scope
      ActionCandidate
        .where(status: "approved")
        .where(
          "department = :department OR action_type IN (:action_types) OR generation_source IN (:sources) OR metadata ->> 'candidate_kind' = :candidate_kind",
          department: "new_business",
          action_types: ActionCandidateBusinessPromoter::NEW_BUSINESS_ACTION_TYPES,
          sources: ActionCandidateBusinessPromoter::NEW_BUSINESS_SOURCES,
          candidate_kind: "new_business"
        )
        .order(created_at: :asc)
    end

    def already_promoted?(candidate)
      candidate.metadata.to_h.dig("business_promotion", "promoted") &&
        Business.real_businesses.exists?(id: candidate.business_id)
    end
  end
end
