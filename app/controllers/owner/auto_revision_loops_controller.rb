module Owner
  class AutoRevisionLoopsController < ApplicationController
    rescue_from ActiveRecord::RecordNotFound, with: :handle_missing_auto_revision_record

    MANUAL_ACTUAL_FIELDS = ActionResult::MANUAL_ACTUAL_FIELDS

    def show
      @board = Aicoo::Owner::AutoRevisionLoopBoard.new(selected_key: params[:selected]).call
    end

    def create_action_result
      candidate = ActionCandidate.find(params.expect(:action_candidate_id))
      result = ActionResult.new(action_result_attributes(candidate))

      if result.save
        evaluate_or_refresh_action_result(result, source: "owner_auto_revision_action_result")
        redirect_to owner_auto_revision_loop_path(selected: "action_candidate:#{candidate.id}", anchor: "selected-task"),
                    notice: "ActionResultを登録しました。7日/14日/30日評価へ進めます。"
      else
        redirect_to owner_auto_revision_loop_path(selected: "action_candidate:#{candidate.id}", anchor: "selected-task"),
                    alert: "ActionResultを登録できません: #{result.errors.full_messages.to_sentence}"
      end
    end

    def create_task
      candidate = ActionCandidate.find(params.expect(:id))
      task = AutoRevisionTask.from_action_candidate(candidate, generated_by: "owner_auto_revision_loop")
      unless task
        redirect_to owner_auto_revision_loop_path(selected: "action_candidate:#{candidate.id}", anchor: "selected-task"),
                    alert: "この候補は#{candidate.execution_mode}のためCodex改修タスクにはしません。Owner Homeで実行単位を確認してください。"
        return
      end
      redirect_to owner_auto_revision_loop_path(selected: "auto_revision_task:#{task.id}", anchor: "selected-task"),
                  notice: "自動改修タスクを作成しました。"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to owner_auto_revision_loop_path(selected: "action_candidate:#{params[:id]}", anchor: "selected-task"),
                  alert: "自動改修タスクを作成できません: #{e.record.errors.full_messages.to_sentence}"
    end

    def approve_task
      task = AutoRevisionTask.find(params.expect(:id))
      result = Aicoo::ApprovalService.approve(task, operator: "owner", source: "owner_auto_revision_loop")
      redirect_to owner_auto_revision_loop_path(selected: "auto_revision_task:#{task.id}", anchor: "selected-task"),
                  notice: result.message
    rescue ActiveRecord::RecordInvalid => e
      redirect_to owner_auto_revision_loop_path(selected: "auto_revision_task:#{params[:id]}", anchor: "selected-task"),
                  alert: "承認できません: #{e.record.errors.full_messages.to_sentence}"
    end

    def start_task
      task = AutoRevisionTask.find(params.expect(:id))
      task.start_implementation!
      redirect_to owner_auto_revision_loop_path(selected: "auto_revision_task:#{task.id}", anchor: "selected-task"),
                  notice: "実装開始として記録しました。"
    end

    def retry_task
      task = AutoRevisionTask.find(params.expect(:id))
      task.enqueue_for_codex!(operator: "owner_auto_revision_loop_retry")
      redirect_to owner_auto_revision_loop_path(selected: "auto_revision_task:#{task.id}", anchor: "selected-task"),
                  notice: "再実行キューへ戻しました。"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to owner_auto_revision_loop_path(selected: "auto_revision_task:#{params[:id]}", anchor: "selected-task"),
                  alert: "再実行できません: #{e.record.errors.full_messages.to_sentence}"
    end

    def mark_task_sent
      task = AutoRevisionTask.find(params.expect(:id))
      task.mark_sent_to_codex!
      redirect_to owner_auto_revision_loop_path(selected: "auto_revision_task:#{task.id}", anchor: "selected-task"),
                  notice: "Codexへ手動送信済みとして記録しました。"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to owner_auto_revision_loop_path(selected: "auto_revision_task:#{params[:id]}", anchor: "selected-task"),
                  alert: "手動送信済みにできません: #{e.record.errors.full_messages.to_sentence}"
    end

    def create_github_issue
      task = AutoRevisionTask.find(params[:id])
      submission_result = Aicoo::CodexSubmissionBuilder.new(task, force: true).call
      unless submission_result.submission && submission_result.reasons.empty?
        message = submission_result.reasons.presence&.join(" / ") || "CodexSubmissionを作成できません。"
        redirect_to owner_auto_revision_loop_path(selected: "auto_revision_task:#{task.id}", anchor: "selected-task"),
                    alert: message
        return
      end

      issue_result = Aicoo::CodexGithubIssueBridge.new(submission_result.submission).call
      redirect_to owner_auto_revision_loop_path(selected: "auto_revision_task:#{task.id}", anchor: "selected-task"),
                  notice: "#{issue_result.message} 開く場所: #{issue_result.issue_url}"
    rescue ActiveRecord::RecordNotFound
      handle_missing_auto_revision_record
    rescue StandardError => e
      redirect_to owner_auto_revision_loop_path(selected: "auto_revision_task:#{params[:id]}", anchor: "selected-task"),
                  alert: "GitHub Issue作成に失敗しました: #{e.message}"
    end

    def create_github_issue_hint
      task = AutoRevisionTask.find(params[:id])
      redirect_to owner_auto_revision_loop_path(selected: "auto_revision_task:#{task.id}", anchor: "selected-task"),
                  alert: "GitHub Issue作成は画面内のボタンから実行してください。"
    rescue ActiveRecord::RecordNotFound
      redirect_to owner_auto_revision_loop_path(anchor: "revision-queue"),
                  alert: "自動改修タスクが見つかりません。最新の改修キューからもう一度操作してください。"
    end

    def record_task_result
      task = AutoRevisionTask.find(params.expect(:id))
      task.record_result!(task_result_params)
      task.create_action_execution_log! if params[:create_action_execution_log] == "1"
      redirect_to owner_auto_revision_loop_path(selected: "auto_revision_task:#{task.id}", anchor: "selected-task"),
                  notice: "実装結果を登録しました。ActionResult登録へ進めます。"
    end

    private

    def action_result_attributes(candidate)
      attrs = params.expect(
        action_result: [
          :executed_on,
          :evaluated_on,
          :actual_revenue_yen,
          :actual_profit_yen,
          :actual_proxy_score_delta,
          :actual_impressions_delta,
          :actual_clicks_delta,
          :actual_sessions_delta,
          :actual_pageviews_delta,
          :actual_phone_clicks_delta,
          :actual_map_clicks_delta,
          :actual_affiliate_clicks_delta,
          :evaluation_status,
          :note,
          metadata: {}
        ]
      ).to_h.symbolize_keys
      attrs.merge(
        action_candidate: candidate,
        business: candidate.business,
        executed_on: attrs[:executed_on].presence || Date.current,
        evaluated_on: attrs[:evaluated_on].presence || Date.current,
        evaluation_status: manual_actual_param_present? ? "pending" : attrs[:evaluation_status].presence || "pending",
        metadata: attrs.fetch(:metadata, {}).to_h.merge(manual_actual_metadata)
      )
    end

    def manual_actual_metadata
      return {} unless manual_actual_param_present?

      {
        "manual_actuals_recorded" => true,
        "manual_actuals_recorded_source" => "owner_auto_revision_action_result",
        "manual_actuals_recorded_at" => Time.current.iso8601
      }
    end

    def manual_actual_param_present?
      raw_params = params[:action_result]
      return false unless raw_params.respond_to?(:key?)

      MANUAL_ACTUAL_FIELDS.any? { |field| actual_param_value_present?(raw_params, field) } ||
        manual_actual_metadata_values(raw_params).any? { |_key, value| value.present? }
    end

    def actual_param_value_present?(raw_params, field)
      value = raw_params[field] || raw_params[field.to_s]
      value.present?
    end

    def manual_actual_metadata_values(raw_params)
      values = raw_params.dig(:metadata, :manual_actuals) || raw_params.dig("metadata", "manual_actuals")
      values.respond_to?(:to_h) ? values.to_h : {}
    end

    def task_result_params
      params.expect(
        auto_revision_task: [
          :status,
          :result_summary,
          :error_message,
          :changed_files,
          :test_result,
          :codex_output,
          :finished_at,
          :commit_sha,
          :pull_request_url,
          :deploy_url,
          :deploy_status
        ]
      )
    end

    def handle_missing_auto_revision_record
      redirect_to owner_auto_revision_loop_path(anchor: "revision-queue"),
                  alert: "対象が見つかりません。最新の改修キューからもう一度操作してください。"
    end

    def evaluate_or_refresh_action_result(action_result, source:)
      if action_result.evaluation_status == "pending" && action_result.evaluated_on <= Date.current
        ActionResultEvaluator.new(action_result).call
      else
        Aicoo::ExpectedValueLearningRefresh.refresh_after_action_result!(action_result, source:)
      end
    rescue StandardError => e
      Rails.logger.warn("[ExpectedValueLearning] evaluation/refresh failed action_result_id=#{action_result.id} source=#{source} error=#{e.class}: #{e.message}")
    end
  end
end
