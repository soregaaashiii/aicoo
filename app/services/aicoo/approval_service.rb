module Aicoo
  class ApprovalService
    Result = Data.define(:record, :action, :message, :metadata, :approval_log, :redirect_record) do
      def redirect_target
        redirect_record || record
      end
    end

    def self.approve(record, operator: "owner", source: "unknown", metadata: {})
      new(record, action: "approve", operator:, source:, metadata:).call
    end

    def self.reject(record, operator: "owner", source: "unknown", metadata: {})
      new(record, action: "reject", operator:, source:, metadata:).call
    end

    def self.pause(record, operator: "owner", source: "unknown", metadata: {})
      new(record, action: "pause", operator:, source:, metadata:).call
    end

    def self.archive(record, operator: "owner", source: "unknown", metadata: {})
      new(record, action: "archive", operator:, source:, metadata:).call
    end

    def self.delete(record, operator: "owner", source: "unknown", metadata: {})
      new(record, action: "delete", operator:, source:, metadata:).call
    end

    def self.approve_all(records, operator: "owner", source: "unknown", metadata: {})
      Array(records).map { |record| approve(record, operator:, source:, metadata:) }
    end

    def initialize(record, action:, operator: "owner", source: "unknown", metadata: {})
      @record = record
      @action = action.to_s
      @operator = operator
      @source = source
      @metadata = metadata.to_h.stringify_keys
    end

    def call
      validate_action!
      previous_status = status_snapshot(record)
      operation = apply_action!
      record.reload if record.persisted?
      new_status = status_snapshot(record)
      approval_log = log!(previous_status:, new_status:, operation:)

      Result.new(
        record:,
        action:,
        message: operation.fetch(:message),
        metadata: operation.fetch(:metadata),
        approval_log:,
        redirect_record: operation[:redirect_record]
      )
    end

    private

    attr_reader :record, :action, :operator, :source, :metadata

    def validate_action!
      return if action.in?(ApprovalLog::ACTIONS)

      raise ArgumentError, "Unsupported approval action: #{action}"
    end

    def apply_action!
      case action
      when "approve"
        approve_record!
      when "reject"
        reject_record!
      when "pause"
        pause_record!
      when "archive"
        archive_record!
      when "delete"
        delete_record!
      else
        raise ArgumentError, "Unsupported approval action: #{action}"
      end
    end

    def approve_record!
      case record
      when ActionCandidate
        approve_action_candidate!
      when AutoRevisionTask
        approve_auto_revision_task!
      when BusinessSerpKeyword
        approve_business_serp_keyword!
      when SerpLandingPageCandidate
        approve_serp_landing_page_candidate!
      when AicooLabExperimentCandidate
        approve_lab_candidate!
      when AicooLabExperiment
        update_approval_status!("approved", "#{record.title} を準備完了にしました。")
      when CodexPromptDraft
        record.approve!
        operation("Codex Prompt Draftを準備完了にしました。")
      when ActionPredictionCalibration
        record.approve!(note: metadata["approval_note"].presence || "ApprovalService")
        operation("#{record.action_type} の補正を反映しました。")
      when CodexQualityCheck
        record.approve!(approved_by: operator, approval_note: metadata["approval_note"])
        operation("Quality Gateを通過にしました。")
      when AicooExecutorTask
        record.approve!
        operation("Executor taskを準備完了にしました。")
      when OpportunityDiscoveryItem
        approve_opportunity!
      else
        generic_approve!
      end
    end

    def reject_record!
      case record
      when ActionCandidate
        record.update!(status: "rejected")
        operation("ActionCandidate『#{record.title}』を却下しました。")
      when AutoRevisionTask
        record.update!(status: "canceled", finished_at: Time.current)
        operation("AutoRevisionTaskを却下しました。")
      when BusinessSerpKeyword
        record.exclude!(reason: metadata["reason"].presence || "Owner rejected")
        operation("検索クエリ候補『#{record.keyword}』を却下し、除外しました。")
      when AicooLabExperimentCandidate
        record.reject!
        operation("新規事業候補『#{record.title}』を却下しました。")
      when AicooLabExperiment
        update_approval_status!("rejected", "#{record.title} を却下しました。")
      when CodexPromptDraft
        record.reject!
        operation("Codex Prompt Draftを却下しました。")
      when ActionPredictionCalibration
        record.reject!(note: metadata["approval_note"].presence || "ApprovalService")
        operation("#{record.action_type} の補正を却下しました。")
      when CodexQualityCheck
        record.reject!(approved_by: operator, approval_note: metadata["approval_note"])
        operation("Quality Gateを却下しました。")
      when AicooExecutorTask
        record.reject!
        operation("Executor taskを却下しました。")
      when OpportunityDiscoveryItem
        record.update!(status: "rejected")
        operation("Opportunity『#{record.title}』を却下しました。")
      else
        generic_reject!
      end
    end

    def pause_record!
      if record.respond_to?(:pause!)
        record.pause!
      elsif record.respond_to?(:mark_status!)
        record.mark_status!("paused")
      elsif record.respond_to?(:status=)
        record.update!(status: "paused")
      else
        raise ActiveRecord::RecordInvalid, record
      end
      operation("#{record_label}を一時停止しました。")
    end

    def archive_record!
      if record.respond_to?(:archive!)
        record.archive!
      elsif record.respond_to?(:status=)
        record.update!(status: "archived")
      else
        raise ActiveRecord::RecordInvalid, record
      end
      operation("#{record_label}をアーカイブしました。")
    end

    def delete_record!
      if record.respond_to?(:discard)
        record.discard
      elsif record.respond_to?(:archive!)
        record.archive!
      elsif record.respond_to?(:status=)
        record.update!(status: "archived")
      else
        raise ActiveRecord::RecordInvalid, record
      end
      operation("#{record_label}を削除扱いにしました。", metadata: { deletion_mode: "non_destructive" })
    end

    def approve_action_candidate!
      if Aicoo::ActionCandidateBusinessPromoter.new_business_candidate?(record)
        promoted_business = nil
        promotion_message = nil
        landing_page = nil

        record.transaction do
          promotion_result = Aicoo::ActionCandidateBusinessPromoter.new(record).call
          promoted_business = promotion_result.business
          promotion_message = promotion_result.message
          promoted_business.update!(
            status: "launched",
            launched: true,
            lifecycle_stage: "lp_validation",
            daily_run_enabled: true,
            serp_enabled: true,
            metadata: promoted_business.metadata.to_h.merge(
              "auto_lp_published" => true,
              "auto_published_at" => Time.current.iso8601
            )
          )
          landing_page = Aicoo::Owner::NewBusinessLandingPageBuilder.new(record).call
          landing_page.publish! unless landing_page.publicly_visible?
          record.update!(
            status: "done",
            approved_at: record.approved_at || Time.current,
            approved_by: record.approved_by.presence || operator
          )
        end

        return operation(
          [
            promotion_message.presence || "Businessを作成しました: #{promoted_business.name}",
            "LPを公開しました: /lp/#{landing_page.published_slug}"
          ].compact.join(" "),
          metadata: {
            business_id: promoted_business.id,
            landing_page_id: landing_page.id,
            published_slug: landing_page.published_slug,
            new_business_candidate: true
          },
          redirect_record: promoted_business
        )
      end

      auto_revision_task = nil
      promotion_message = nil

      record.transaction do
        if record.status == "approved"
          promotion_result = Aicoo::ActionCandidateBusinessPromoter.new(record).call
          auto_revision_task = AutoRevisionTask.active.find_by(action_candidate: record) ||
                               AutoRevisionTask.from_action_candidate(record, generated_by: "approval_service_recovery")
          auto_revision_task&.approve! if auto_revision_task&.status&.in?(%w[draft waiting_approval])
          promotion_message = [
            "すでに準備完了です。既存のAutoRevisionTaskへ紐付けました。",
            promotion_result&.message
          ].compact.join(" ")
        else
          auto_revision_task = record.approve!(approved_by: operator)
          promotion_message = record.business_promotion_result&.message
        end
      end

      unless auto_revision_task
        return operation(
          [
            promotion_message,
            "ActionCandidate『#{record.title}』は#{record.execution_mode}の実行タスクとして準備しました。Codex改修タスクは作成しません。"
          ].compact.join(" "),
          metadata: {
            execution_mode: record.execution_mode,
            business_id: record.reload.business_id
          },
          redirect_record: record
        )
      end

      operation(
        [
          promotion_message,
          "ActionCandidate『#{record.title}』の改修を開始し、AutoRevisionTask ##{auto_revision_task.id} を作成または確認しました。"
        ].compact.join(" "),
        metadata: {
          auto_revision_task_id: auto_revision_task.id,
          auto_revision_task_status: auto_revision_task.status,
          business_id: record.reload.business_id
        },
        redirect_record: auto_revision_task
      )
    end

    def approve_auto_revision_task!
      if record.status.in?(%w[ready_for_codex approved queued sent_to_codex running completed succeeded partial_succeeded])
        return operation("AutoRevisionTaskはすでにCodex準備済みです。", metadata: { idempotent: true })
      end

      record.approve!
      operation("AutoRevisionTaskをCodex準備済みにしました。", metadata: { auto_revision_task_status: record.status })
    end

    def approve_business_serp_keyword!
      summary = Aicoo::Serp::CandidatePromoter.promote!([ record ])
      result = summary.results.first
      status_word =
        case result.status
        when "created" then "追加"
        when "updated" then "既存の検索クエリへ反映"
        else "skip"
        end

      operation(
        "AI候補『#{record.keyword}』を実行対象の検索クエリに#{status_word}しました。追加だけではSERP取得は実行されません。",
        metadata: {
          serp_query_id: result.serp_query&.id,
          promoter_status: result.status
        },
        redirect_record: result.serp_query || record
      )
    end

    def approve_serp_landing_page_candidate!
      landing_page = record.create_draft_landing_page!
      operation(
        "LP候補『#{record.lp_title}』からLPを作成しました。次はLP公開です。",
        metadata: {
          landing_page_id: landing_page.id,
          business_id: landing_page.business_id
        },
        redirect_record: landing_page
      )
    end

    def approve_lab_candidate!
      business = record.approve!
      operation(
        "事業を作成しました: #{business.name}",
        metadata: { business_id: business.id },
        redirect_record: business
      )
    end

    def approve_opportunity!
      created_business = nil
      if record.new_service_candidate?
        created_business = Aicoo::OpportunityBusinessBuilder.new(record).call
      else
        record.update!(status: "approved")
      end

      operation(
        created_business ? "Businessを作成しました: #{created_business.name}" : "Opportunity『#{record.title}』を準備完了にしました。",
        metadata: { business_id: created_business&.id || record.business_id },
        redirect_record: created_business || record
      )
    end

    def update_approval_status!(approval_status, message)
      record.update!(approval_status:)
      operation(message)
    end

    def generic_approve!
      if record.respond_to?(:approve!)
        record.approve!
      elsif record.respond_to?(:status=)
        record.update!(status: "approved")
      else
        raise ArgumentError, "#{record.class.name} does not support approval"
      end
      operation("#{record_label}を準備完了にしました。")
    end

    def generic_reject!
      if record.respond_to?(:reject!)
        record.reject!
      elsif record.respond_to?(:status=)
        record.update!(status: "rejected")
      else
        raise ArgumentError, "#{record.class.name} does not support rejection"
      end
      operation("#{record_label}を却下しました。")
    end

    def operation(message, metadata: {}, redirect_record: nil)
      {
        message:,
        metadata: self.metadata.merge(metadata.stringify_keys),
        redirect_record:
      }
    end

    def log!(previous_status:, new_status:, operation:)
      ApprovalLog.create!(
        approvable: record,
        business: business_for(record),
        action:,
        operator:,
        source:,
        previous_status: previous_status[:raw],
        new_status: new_status[:raw],
        common_previous_status: previous_status[:common],
        common_new_status: new_status[:common],
        idempotent: operation.fetch(:metadata).to_h["idempotent"].present?,
        message: operation.fetch(:message),
        metadata: operation.fetch(:metadata).merge(
          "redirect_record_type" => operation[:redirect_record]&.class&.name,
          "redirect_record_id" => operation[:redirect_record]&.id
        ).compact,
        approved_at: Time.current
      )
    end

    def status_snapshot(target)
      raw =
        if target.respond_to?(:approval_status) && target.approval_status.present?
          target.approval_status
        elsif target.respond_to?(:status)
          target.status
        end

      { raw:, common: common_status(raw) }
    end

    def common_status(status)
      case status.to_s
      when "draft", "new", "idea", "proposed", "preview_ready", "approval_pending", "pending", "waiting_approval", "approval", "not_required"
        "pending"
      when "approved", "ready_for_codex", "queued", "sent_to_codex", "active"
        "approved"
      when "running", "building", "processing"
        "running"
      when "done", "success", "succeeded", "completed", "converted", "published", "copied", "executed"
        "completed"
      when "rejected", "failed", "canceled", "cancelled"
        "rejected"
      when "archived", "paused", "excluded"
        "archived"
      else
        status.presence
      end
    end

    def business_for(target)
      return target.business if target.respond_to?(:business)
      return target.action_candidate&.business if target.respond_to?(:action_candidate)
      return target.auto_revision_task&.business if target.respond_to?(:auto_revision_task)

      nil
    end

    def record_label
      if record.respond_to?(:title)
        "『#{record.title}』"
      elsif record.respond_to?(:name)
        "『#{record.name}』"
      else
        "#{record.class.name} ##{record.id}"
      end
    end
  end
end
