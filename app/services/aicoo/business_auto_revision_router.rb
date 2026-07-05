module Aicoo
  class BusinessAutoRevisionRouter
    Result = Data.define(:task, :log, :action)

    def initialize(action_candidate, generated_by: "auto_queue")
      @action_candidate = action_candidate
      @business = action_candidate.business
      @generated_by = generated_by
    end

    def call
      return log_non_code_revision unless action_candidate.code_revision_execution_mode?

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

    def log_non_code_revision
      log = create_log!(
        task: nil,
        risk_level: "low",
        status: "pending",
        message: "execution_mode=#{action_candidate.execution_mode}: Codexへ投げない実行タスクとして扱います。",
        action: "non_code_revision",
        metadata: {
          "execution_mode" => action_candidate.execution_mode,
          "seo_action_type" => action_candidate.metadata.to_h["seo_action_type"]
        }
      )
      Result.new(task: nil, log:, action: "non_code_revision")
    end

    def log_manual(task, risk_level)
      task.update!(status: "draft") unless task.status == "draft"
      log = create_log!(task:, risk_level:, status: "pending", message: "manual: 提案のみ作成しました。", action: "manual_proposal")
      Result.new(task:, log:, action: "manual_proposal")
    end

    def log_approval(task, risk_level)
      reason = owner_approval_reason(task, risk_level)
      unless reason
        task.update!(status: "ready_for_codex", approved_at: task.approved_at || Time.current)
        log = create_log!(
          task:,
          risk_level:,
          status: "pending",
          message: "Owner判断が必要な理由がないため、Codex準備へ自動で進めました。",
          action: "auto_released_no_owner_approval_reason",
          metadata: { "owner_approval_required" => false }
        )
        return Result.new(task:, log:, action: "auto_released_no_owner_approval_reason")
      end

      task.update!(
        status: "waiting_approval",
        metadata: task.metadata.to_h.merge(
          "approval_required_reason" => reason,
          "owner_approval" => task.metadata.to_h["owner_approval"].to_h.merge(
            "required" => true,
            "reason" => reason,
            "reason_code" => owner_approval_reason_code(reason),
            "recorded_at" => Time.current.iso8601
          )
        )
      ) unless task.status == "waiting_approval" && task.approval_required_reason.present?
      action = business.automatic_auto_revision? ? "approval_required_due_to_risk" : "approval_required"
      log = create_log!(
        task:,
        risk_level:,
        status: "queued_for_approval",
        message: "Owner判断が必要です: #{reason}",
        action:,
        metadata: {
          "owner_approval_required" => true,
          "approval_required_reason" => reason,
          "approval_required_reason_code" => owner_approval_reason_code(reason)
        }
      )
      Result.new(task:, log:, action:)
    end

    def route_automatic(task, risk_level)
      return log_approval(task, risk_level) if owner_approval_reason(task, risk_level).present?

      precheck = Aicoo::AutoRevisionPrecheck.new(business).call
      unless precheck.ok
        task.update!(status: "failed", error_message: precheck.errors.join(" / "))
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
      dispatch = Aicoo::AutoRevisionCodexIssueDispatcher.new.call(tasks: [ task ], limit: 1)
      detail = dispatch.details.first.to_h

      unless detail["status"].in?(%w[created already_created])
        message = [
          detail["reason"],
          detail["message"],
          Array(detail["reasons"]).join(" / ")
        ].compact_blank.join(": ")
        task.update!(status: "failed", error_message: message.presence || "GitHub Issue作成に失敗しました。")
        log = create_log!(
          task:,
          risk_level:,
          status: "failed",
          message: task.error_message,
          action: "github_issue_failed",
          metadata: { "dispatch_detail" => detail, "precheck_warnings" => precheck.warnings }
        )
        return Result.new(task:, log:, action: "github_issue_failed")
      end

      log = create_log!(
        task:,
        risk_level:,
        status: "sent_to_codex",
        started_at: Time.current,
        message: "automatic: 低リスクのためGitHub Issue作成まで自動実行しました。Cloud Codex API連携は未実装のため、Issue上でCodex作業待ちです。",
        action: "sent_to_codex",
        metadata: {
          "precheck_warnings" => precheck.warnings,
          "deploy_requires_approval" => true,
          "github_issue_url" => detail["issue_url"],
          "github_issue_number" => detail["issue_number"],
          "cloud_codex_api_status" => "pending"
        }
      )
      Result.new(task:, log:, action: "sent_to_codex")
    rescue ActiveRecord::RecordInvalid => e
      task.update!(status: "failed", error_message: e.record.errors.full_messages.to_sentence) if task.persisted?
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

    def owner_approval_reason(task, risk_level)
      task.approval_required_reason.presence ||
        inferred_owner_approval_reason(task).presence ||
        (risk_level == "high" ? "高リスク改修のためOwner判断が必要です。" : nil)
    end

    def inferred_owner_approval_reason(task)
      text = owner_approval_signal_text(task)

      return "本番破壊的変更の可能性があるためOwner判断が必要です。" if text.match?(/db:drop|db:reset|drop database|destroy_all|delete_all|破壊/)
      return "新しいお金または既存予算超過が発生する可能性があるためOwner判断が必要です。" if text.match?(/課金|広告費|予算|支払い|費用|cost|billing/)
      return "法的リスクまたは規約リスクがあるためOwner判断が必要です。" if text.match?(/法務|法律|規約|legal|privacy|個人情報/)
      return "ブランド変更を含む可能性があるためOwner判断が必要です。" if text.match?(/ブランド|brand|サービス名|ロゴ/)
      return "サービス方針変更を含む可能性があるためOwner判断が必要です。" if text.match?(/方針|pivot|価格変更|料金変更|撤退|統合/)

      nil
    end

    def owner_approval_signal_text(task)
      [
        task.title,
        task.changed_files,
        task.metadata.to_h["evaluation_reason"],
        task.metadata.to_h["action_type"],
        action_candidate.title,
        action_candidate.description,
        action_candidate.action_type,
        action_candidate.evaluation_reason
      ].compact.join(" ").downcase
    end

    def owner_approval_reason_code(reason)
      case reason
      when /お金|予算|費用|課金/
        "money_or_budget"
      when /方針|価格|料金|撤退|統合/
        "strategy_change"
      when /破壊|db:drop|db:reset/
        "destructive_production_change"
      when /法的|法務|規約|個人情報/
        "legal_risk"
      when /ブランド|ロゴ/
        "brand_change"
      when /高リスク/
        "high_risk"
      else
        "owner_only_decision"
      end
    end
  end
end
