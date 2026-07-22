module Aicoo
  class AutoRevisionAutopilot
    Result = Data.define(:ran, :task, :log, :reason, :message)

    def self.call(action_candidate, generated_by: "auto_revision_autopilot")
      new(action_candidate, generated_by:).call
    end

    def self.sweep(limit: 20, generated_by: "auto_revision_autopilot_sweep")
      candidates = AicooAutoRevisionQueueBuilderService.candidate_scope
        .joins(:business)
        .where(businesses: { auto_revision_mode: "automatic" })
        .where.not(department: "new_business")
        .limit(limit)

      candidates.map { |candidate| call(candidate, generated_by:) }
    end

    def initialize(action_candidate, generated_by: "auto_revision_autopilot")
      @action_candidate = action_candidate
      @generated_by = generated_by
    end

    def call
      return skipped("missing_candidate") unless action_candidate
      return skipped("missing_business") unless business
      return skipped("not_automatic") unless business.automatic_auto_revision?
      return skipped("new_business_candidate") if action_candidate.department == "new_business"
      return skipped("manual_task_creation_only") if action_candidate.metadata.to_h["manual_task_creation_only"] == true
      return skipped("inactive_candidate") if action_candidate.status.in?(ActionCandidate::INACTIVE_STATUSES)
      return skipped("missing_execution_prompt") if action_candidate.execution_prompt.blank?
      readiness = Aicoo::ActionCandidateExecutionReadiness.call(action_candidate)
      return skipped("execution_readiness:#{readiness.readiness}") unless readiness.ready?

      route = Aicoo::BusinessAutoRevisionRouter.new(action_candidate, generated_by:).call
      Result.new(
        ran: true,
        task: route.task,
        log: route.log,
        reason: route.action,
        message: route.log&.message
      )
    rescue StandardError => e
      Rails.logger.warn("[AutoRevisionAutopilot] ActionCandidate##{action_candidate&.id} failed: #{e.class} #{e.message}")
      Result.new(ran: false, task: nil, log: nil, reason: "exception", message: "#{e.class}: #{e.message}")
    end

    private

    attr_reader :action_candidate, :generated_by

    def business
      action_candidate.business
    end

    def skipped(reason)
      Result.new(ran: false, task: action_candidate&.auto_revision_tasks&.active&.first, log: nil, reason:, message: reason)
    end
  end
end
