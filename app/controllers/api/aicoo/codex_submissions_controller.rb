module Api
  module Aicoo
    class CodexSubmissionsController < ActionController::API
      before_action :authenticate_callback_token!

      def github_tracking
        codex_submission = CodexSubmission.find(params[:id])
        codex_submission.update_tracking!(tracking_attributes.merge(tracking_updated_by: "github_actions"))
        codex_submission.mark_failed!(params[:error_message]) if params[:status].to_s == "failed" && params[:error_message].present?

        render json: {
          ok: true,
          codex_submission_id: codex_submission.id,
          workflow_status: codex_submission.workflow_status,
          pull_request_url: codex_submission.pr_url
        }
      rescue ActiveRecord::RecordNotFound
        render json: { ok: false, error: "codex_submission_not_found" }, status: :not_found
      rescue ActiveRecord::RecordInvalid => e
        render json: { ok: false, error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      rescue StandardError => e
        Rails.logger.error("[Codex Callback API] failed #{e.class}: #{e.message}")
        render json: { ok: false, error: "#{e.class}: #{e.message}" }, status: :internal_server_error
      end

      private

      def authenticate_callback_token!
        expected = ENV["AICOO_CODEX_CALLBACK_TOKEN"].presence ||
          ENV["AICOO_ACTIVITY_API_TOKEN"].presence ||
          ENV["AICOO_API_KEY"].presence
        token_valid = expected.present? && secure_compare(bearer_token, expected)
        Rails.logger.info(
          "[Codex Callback API] authorization_present=#{bearer_token.present?} " \
          "token_valid=#{token_valid} expected_configured=#{expected.present?}"
        )
        return if token_valid

        render json: { ok: false, error: "unauthorized" }, status: :unauthorized
      end

      def secure_compare(value, expected)
        ActiveSupport::SecurityUtils.secure_compare(
          Digest::SHA256.hexdigest(value.to_s),
          Digest::SHA256.hexdigest(expected.to_s)
        )
      end

      def bearer_token
        authorization = request.headers["Authorization"].to_s
        return authorization.delete_prefix("Bearer ").strip if authorization.start_with?("Bearer ")

        request.headers["X-AICOO-API-Key"].to_s
      end

      def tracking_attributes
        payload = params.permit(
          :pull_request_url,
          :pr_url,
          :pr_status,
          :review_status,
          :ci_status,
          :test_result,
          :merge_status,
          :deploy_status,
          :commit_sha,
          :result_summary,
          :github_issue_url,
          :github_issue_number,
          :github_actions_run_id,
          :github_actions_run_url,
          changed_files: []
        ).to_h
        payload["pull_request_url"] = payload["pull_request_url"].presence || payload.delete("pr_url")
        payload.compact_blank
      end
    end
  end
end
