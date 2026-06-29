module Aicoo
  class AutoRevisionPrecheck
    Result = Data.define(:ok, :errors, :warnings)

    def initialize(business)
      @business = business
    end

    def call
      errors = []
      warnings = []

      errors << "Google接続が未設定です" unless google_connected?
      errors << "Execution Profileが未設定です" unless execution_profile_configured?
      errors << "前回の自動改訂が失敗しています" if previous_failure?
      warnings << "Git cleanは実行時確認が必要です"
      warnings << "デプロイは承認制です"

      Result.new(ok: errors.empty?, errors:, warnings:)
    end

    private

    attr_reader :business

    def google_connected?
      AicooGoogleCredential.default&.refresh_token.present?
    end

    def execution_profile_configured?
      return true if business.aicoo_internal_codex?

      profile = business.business_execution_profile
      profile&.active? && profile.coverage_status == "configured"
    end

    def previous_failure?
      business.auto_revision_run_logs.recent.first&.status == "failed"
    end
  end
end
