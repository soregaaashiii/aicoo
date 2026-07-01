module Aicoo
  class ExternalCommitImporter
    Result = Data.define(:business_activity_log, :action_execution_log, :action_result, :auto_revision_task, :created_execution_log)

    def initialize(params)
      @params = params.to_h.symbolize_keys
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        task = auto_revision_task
        execution_log = find_or_create_execution_log!(task)
        action_result = upsert_action_result!(execution_log)
        activity_log = record_activity_log!(task, execution_log, action_result)
        complete_task!(task) if task
        action_candidate.update!(status: "done")

        Result.new(
          business_activity_log: activity_log,
          action_execution_log: execution_log,
          action_result: action_result,
          auto_revision_task: task,
          created_execution_log: @created_execution_log == true
        )
      end
    end

    private

    attr_reader :params

    def validate!
      raise ArgumentError, "Businessを選択してください。" unless business
      raise ArgumentError, "ActionCandidateを選択してください。" unless action_candidate
      raise ArgumentError, "commit SHAを入力してください。" if commit_sha.blank?
      return if action_candidate.business_id == business.id

      raise ArgumentError, "選択したActionCandidateはBusiness「#{business.name}」に属していません。"
    end

    def find_or_create_execution_log!(task)
      existing = action_candidate.action_execution_logs.includes(:business).to_a.find do |log|
        log.metadata.to_h["commit_sha"].to_s == commit_sha
      end
      return existing if existing

      @created_execution_log = true
      action_candidate.action_execution_logs.create!(
        business:,
        planned_action: action_candidate.execution_prompt.presence || action_candidate.description.presence || action_candidate.title,
        actual_action: actual_action_summary,
        status: "completed",
        started_at: executed_at,
        finished_at: executed_at,
        human_note: "外部commitをAICOOへ取り込みました。",
        metadata: {
          "source" => "external_commit_import",
          "commit_sha" => commit_sha,
          "repository" => repository,
          "changed_files" => changed_files,
          "auto_revision_task_id" => task&.id,
          "imported_at" => Time.current.iso8601
        }.compact
      )
    end

    def upsert_action_result!(execution_log)
      result = action_candidate.action_result || action_candidate.build_action_result(
        business:,
        executed_on: executed_at.to_date,
        evaluated_on: Date.current,
        actual_revenue_yen: params[:actual_revenue_yen].to_i,
        actual_profit_yen: params[:actual_profit_yen].to_i,
        evaluation_status: "pending"
      )
      result.assign_attributes(
        business:,
        executed_on: result.executed_on || executed_at.to_date,
        evaluated_on: Date.current,
        note: merged_note(result),
        metadata: result.metadata.to_h.deep_merge(
          "external_commit_import" => {
            "commit_sha" => commit_sha,
            "repository" => repository,
            "changed_files" => changed_files,
            "action_execution_log_id" => execution_log.id,
            "auto_revision_task_id" => auto_revision_task&.id,
            "imported_at" => Time.current.iso8601
          }.compact
        )
      )
      result.save!
      execution_log.update!(action_result: result)
      result
    end

    def record_activity_log!(task, execution_log, action_result)
      BusinessActivityLog.record!(
        business:,
        attributes: {
          source_app: repository.presence || "external_repo",
          activity_type: "code_revision_imported",
          resource_type: "commit",
          resource_id: commit_sha,
          title: "#{business.name}の外部commitを取り込み",
          occurred_at: executed_at,
          detected_at: Time.current,
          diff_summary: actual_action_summary,
          metadata: {
            "repository" => repository,
            "commit_sha" => commit_sha,
            "changed_files" => changed_files,
            "action_candidate_id" => action_candidate.id,
            "action_execution_log_id" => execution_log.id,
            "action_result_id" => action_result.id,
            "auto_revision_task_id" => task&.id,
            "imported_by" => "admin_external_commit_import"
          }.compact,
          source_method: "logger",
          idempotency_key: "external_commit_import:#{business.id}:#{commit_sha}"
        }
      )
    end

    def complete_task!(task)
      return if task.status.in?(%w[completed succeeded partial_succeeded])

      task.record_result!(
        status: "completed",
        result_summary: actual_action_summary,
        changed_files: changed_files.join("\n"),
        test_result: params[:test_result],
        codex_output: "外部commit取り込みによって完了扱いにしました。",
        finished_at: executed_at,
        commit_sha:
      )
    end

    def merged_note(result)
      imported_note = [
        "外部commit取り込み",
        "commit: #{commit_sha}",
        ("repository: #{repository}" if repository.present?),
        ("変更ファイル: #{changed_files.join(', ')}" if changed_files.any?),
        params[:result_summary].presence
      ].compact.join("\n")

      [ result.note.presence, imported_note ].compact.join("\n\n")
    end

    def actual_action_summary
      params[:result_summary].presence ||
        "外部commit #{commit_sha} をAICOOへ取り込みました。#{changed_files.any? ? "変更ファイル: #{changed_files.join(', ')}" : ''}".strip
    end

    def business
      @business ||= Business.find_by(id: params[:business_id])
    end

    def action_candidate
      @action_candidate ||= ActionCandidate.find_by(id: params[:action_candidate_id])
    end

    def auto_revision_task
      @auto_revision_task ||= if params[:auto_revision_task_id].present?
        AutoRevisionTask.find_by(id: params[:auto_revision_task_id])
      else
        action_candidate.auto_revision_tasks.recent.first
      end
    end

    def commit_sha
      @commit_sha ||= params[:commit_sha].to_s.strip
    end

    def repository
      params[:repository].to_s.strip.presence
    end

    def changed_files
      @changed_files ||= params[:changed_files].to_s.lines.map(&:strip).compact_blank
    end

    def executed_at
      @executed_at ||= Time.zone.parse(params[:executed_at].to_s).presence || Time.current
    rescue ArgumentError, TypeError
      Time.current
    end
  end
end
