module Aicoo
  class BusinessAutoRevisionRouter
    Result = Data.define(:task, :log, :action)

    def initialize(action_candidate, generated_by: "auto_queue")
      @action_candidate = action_candidate
      @business = action_candidate.business
      @generated_by = generated_by
    end

    def call
      task = AutoRevisionTask.from_action_candidate(action_candidate, generated_by:)
      risk_level = task.risk_level

      case business.auto_revision_mode
      when "manual"
        log_manual(task, risk_level)
      when "approval"
        log_approval(task, risk_level)
      when "automatic"
        route_automatic(task, risk_level)
      else
        log_manual(task, risk_level)
      end
    end

    private

    attr_reader :action_candidate, :business, :generated_by

    def log_manual(task, risk_level)
      task.update!(status: "draft") unless task.status == "draft"
      log = create_log!(task:, risk_level:, status: "pending", message: "manual: 提案のみ作成しました。", action: "manual_proposal")
      Result.new(task:, log:, action: "manual_proposal")
    end

    def log_approval(task, risk_level)
      task.update!(status: "waiting_approval") unless task.status == "waiting_approval"
      action = business.automatic_auto_revision? ? "approval_required_due_to_risk" : "approval_required"
      log = create_log!(task:, risk_level:, status: "queued_for_approval", message: "approval: 承認待ちに追加しました。", action:)
      Result.new(task:, log:, action:)
    end

    def route_automatic(task, risk_level)
      return log_approval(task, risk_level) unless risk_level == "low"

      precheck = Aicoo::AutoRevisionPrecheck.new(business).call
      unless precheck.ok
        task.update!(status: "waiting_approval")
        log = create_log!(
          task:,
          risk_level:,
          status: "precheck_failed",
          message: precheck.errors.join(" / "),
          action: "precheck_failed",
          metadata: { "precheck_errors" => precheck.errors, "precheck_warnings" => precheck.warnings }
        )
        return Result.new(task:, log:, action: "precheck_failed")
      end

      task.approve! unless task.status == "ready_for_codex"
      task.mark_sent_to_codex!
      log = create_log!(
        task:,
        risk_level:,
        status: "sent_to_codex",
        started_at: Time.current,
        message: "automatic: 低リスクのためCodex送信準備まで進めました。Deployは承認待ちです。",
        action: "sent_to_codex",
        metadata: { "precheck_warnings" => precheck.warnings, "deploy_requires_approval" => true }
      )
      Result.new(task:, log:, action: "sent_to_codex")
    rescue ActiveRecord::RecordInvalid => e
      task.update!(status: "waiting_approval") if task.persisted?
      log = create_log!(
        task:,
        risk_level:,
        status: "precheck_failed",
        message: e.record.errors.full_messages.to_sentence,
        action: "precheck_failed"
      )
      Result.new(task:, log:, action: "precheck_failed")
    end

    def create_log!(task:, risk_level:, status:, message:, action:, started_at: nil, metadata: {})
      AutoRevisionRunLog.create!(
        business:,
        auto_revision_task: task,
        status:,
        auto_revision_mode: business.auto_revision_mode,
        risk_level:,
        started_at:,
        message:,
        metadata: metadata.merge(
          "action_candidate_id" => action_candidate.id,
          "action" => action,
          "generated_by" => generated_by,
          "deploy_requires_approval" => true
        )
      )
    end
  end
end
