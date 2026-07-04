module Aicoo
  class CodexResultImporter
    Result = Data.define(:codex_submission, :auto_revision_task, :action_execution_log, :action_result, :business_activity_log)

    def initialize(codex_submission, params = {})
      @codex_submission = codex_submission
      @params = params.to_h.symbolize_keys
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        sync_tracking!
        task.record_result!(task_result_attributes)
        execution_log = upsert_execution_log!
        action_result = upsert_action_result!(execution_log)
        activity_log = record_activity_log!(execution_log, action_result)
        candidate.update!(status: "done")
        codex_submission.mark_completed!(payload: completion_payload(action_result, execution_log, activity_log))

        Result.new(
          codex_submission:,
          auto_revision_task: task,
          action_execution_log: execution_log,
          action_result:,
          business_activity_log: activity_log
        )
      end
    end

    private

    attr_reader :codex_submission, :params

    def validate!
      raise ArgumentError, "CodexSubmissionがありません。" unless codex_submission
      raise ArgumentError, "AutoRevisionTaskがありません。" unless task
      raise ArgumentError, "ActionCandidateがありません。" unless candidate
      raise ArgumentError, "実装内容を入力してください。" if result_summary.blank?
    end

    def sync_tracking!
      codex_submission.update_tracking!(
        pull_request_url: pull_request_url,
        pr_status: pull_request_url.present? ? "pr_created" : nil,
        ci_status: params[:ci_status].presence,
        test_result: params[:test_result].presence,
        merge_status: params[:merge_status].presence,
        deploy_status: params[:deploy_status].presence
      )
    end

    def task_result_attributes
      {
        status: params[:status].presence || "completed",
        result_summary:,
        error_message: params[:error_message],
        changed_files: changed_files.join("\n"),
        test_result: params[:test_result],
        codex_output: params[:codex_output].presence || "CodexSubmission ##{codex_submission.id} の実装結果を取り込みました。",
        finished_at: executed_at,
        commit_sha: params[:commit_sha],
        pull_request_url: pull_request_url,
        deploy_url: params[:deploy_url],
        deploy_status: params[:deploy_status]
      }
    end

    def upsert_execution_log!
      existing = candidate.action_execution_logs.to_a.find do |log|
        log.metadata.to_h["codex_submission_id"].to_i == codex_submission.id
      end

      log = existing || candidate.action_execution_logs.build
      log.assign_attributes(
        business:,
        planned_action: candidate.execution_prompt.presence || candidate.description.presence || candidate.title,
        actual_action: result_summary,
        status: execution_status,
        started_at: task.started_at || codex_submission.submitted_at || codex_submission.created_at,
        finished_at: executed_at,
        human_note: "Codex実装結果をAICOOへ取り込みました。",
        metadata: log.metadata.to_h.merge(
          "source" => "codex_result_import",
          "codex_submission_id" => codex_submission.id,
          "auto_revision_task_id" => task.id,
          "pull_request_url" => pull_request_url,
          "commit_sha" => params[:commit_sha],
          "changed_files" => changed_files,
          "imported_at" => Time.current.iso8601
        ).compact_blank
      )
      log.save!
      log
    end

    def upsert_action_result!(execution_log)
      result = candidate.action_result || candidate.build_action_result
      result.assign_attributes(
        business:,
        executed_on: executed_at.to_date,
        evaluated_on: Date.current,
        actual_revenue_yen: params[:actual_revenue_yen].to_i,
        actual_profit_yen: params[:actual_profit_yen].to_i,
        evaluation_status: params[:evaluation_status].presence || "pending",
        note: result_note(result),
        metadata: result.metadata.to_h.deep_merge(
          "codex_result_import" => {
            "codex_submission_id" => codex_submission.id,
            "auto_revision_task_id" => task.id,
            "action_execution_log_id" => execution_log.id,
            "pull_request_url" => pull_request_url,
            "commit_sha" => params[:commit_sha],
            "changed_files" => changed_files,
            "imported_at" => Time.current.iso8601
          }.compact
        )
      )
      result.save!
      execution_log.update!(action_result: result)
      result
    end

    def record_activity_log!(execution_log, action_result)
      BusinessActivityLog.record!(
        business:,
        attributes: {
          source_app: codex_submission.repository_url.presence || "codex",
          activity_type: "codex_revision_imported",
          resource_type: "pull_request",
          resource_id: pull_request_url.presence || "codex_submission:#{codex_submission.id}",
          title: "#{business.name}のCodex改修結果を取り込み",
          occurred_at: executed_at,
          detected_at: Time.current,
          diff_summary: result_summary,
          metadata: {
            "codex_submission_id" => codex_submission.id,
            "auto_revision_task_id" => task.id,
            "action_candidate_id" => candidate.id,
            "action_execution_log_id" => execution_log.id,
            "action_result_id" => action_result.id,
            "pull_request_url" => pull_request_url,
            "commit_sha" => params[:commit_sha],
            "changed_files" => changed_files,
            "imported_by" => "codex_result_importer"
          }.compact,
          source_method: "logger",
          idempotency_key: "codex_result_import:#{business.id}:#{codex_submission.id}"
        }
      )
    end

    def completion_payload(action_result, execution_log, activity_log)
      {
        "codex_result_imported_at" => Time.current.iso8601,
        "action_result_id" => action_result.id,
        "action_execution_log_id" => execution_log.id,
        "business_activity_log_id" => activity_log.id,
        "pull_request_url" => pull_request_url,
        "commit_sha" => params[:commit_sha]
      }.compact_blank
    end

    def result_note(result)
      imported_note = [
        "Codex実装結果取り込み",
        ("PR: #{pull_request_url}" if pull_request_url.present?),
        ("commit: #{params[:commit_sha]}" if params[:commit_sha].present?),
        ("変更ファイル: #{changed_files.join(', ')}" if changed_files.any?),
        result_summary
      ].compact.join("\n")

      [ result.note.presence, imported_note ].compact.join("\n\n")
    end

    def task
      @task ||= codex_submission.auto_revision_task
    end

    def candidate
      @candidate ||= task.action_candidate
    end

    def business
      @business ||= codex_submission.business
    end

    def result_summary
      @result_summary ||= params[:result_summary].to_s.strip
    end

    def pull_request_url
      @pull_request_url ||= params[:pull_request_url].presence || codex_submission.pr_url
    end

    def changed_files
      @changed_files ||= params[:changed_files].to_s.lines.map(&:strip).compact_blank
    end

    def executed_at
      @executed_at ||= Time.zone.parse(params[:executed_at].to_s).presence || Time.current
    rescue ArgumentError, TypeError
      Time.current
    end

    def execution_status
      return "failed" if params[:status].to_s == "failed"
      return "partial" if params[:status].to_s == "partial_succeeded"

      "completed"
    end
  end
end
