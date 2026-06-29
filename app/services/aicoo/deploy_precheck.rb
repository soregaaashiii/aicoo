module Aicoo
  class DeployPrecheck
    Result = Data.define(:ok, :errors, :warnings, :checks, :rollback_commit)

    def initialize(
      business,
      risk_level: nil,
      tests_passed: nil,
      git_clean: nil,
      target_branch: nil,
      rollback_commit: nil,
      previous_deploy_failed: nil
    )
      @business = business
      @risk_level = risk_level
      @tests_passed = tests_passed
      @git_clean = git_clean
      @target_branch = target_branch
      @rollback_commit = rollback_commit
      @previous_deploy_failed = previous_deploy_failed
    end

    def call
      errors = []
      warnings = []
      checks = {
        "auto_revision_automatic" => business.automatic_auto_revision?,
        "risk_low" => risk_level == "low",
        "tests_passed" => tests_passed?,
        "deploy_command_exists" => deploy_command.present?,
        "git_clean" => git_clean?,
        "target_branch_correct" => target_branch_correct?,
        "rollback_commit_saved" => rollback_commit_value.present?,
        "google_health_ok" => google_health_ok?,
        "no_recent_critical_error" => no_recent_critical_error?,
        "previous_deploy_not_failed" => !previous_deploy_failed?
      }

      errors << "Auto Revision Modeがautomaticではありません" unless checks["auto_revision_automatic"]
      errors << "riskがlowではありません" unless checks["risk_low"]
      errors << "テスト成功が確認できません" unless checks["tests_passed"]
      errors << "deploy_commandが未設定です" unless checks["deploy_command_exists"]
      errors << "Git cleanが確認できません" unless checks["git_clean"]
      errors << "対象branchが一致していません" unless checks["target_branch_correct"]
      errors << "rollback commitが保存されていません" unless checks["rollback_commit_saved"]
      errors << "Google/GA4/GSCに重大な異常があります" unless checks["google_health_ok"]
      errors << "直近の重大エラーがあります" unless checks["no_recent_critical_error"]
      errors << "前回Deployが失敗しています" unless checks["previous_deploy_not_failed"]
      warnings << "自動DeployはPrecheck通過時だけDeployStartedイベントを記録します"

      Result.new(ok: errors.empty?, errors:, warnings:, checks:, rollback_commit: rollback_commit_value)
    end

    private

    attr_reader :business, :risk_level, :tests_passed, :git_clean, :target_branch, :rollback_commit, :previous_deploy_failed

    def deploy_command
      business.codex_execution_target_config[:deploy_command]
    end

    def tests_passed?
      ActiveModel::Type::Boolean.new.cast(tests_passed)
    end

    def git_clean?
      ActiveModel::Type::Boolean.new.cast(git_clean)
    end

    def target_branch_correct?
      expected = business.codex_execution_target_config[:default_branch].presence || "main"
      actual = target_branch.presence || expected
      actual == expected
    end

    def rollback_commit_value
      rollback_commit.presence
    end

    def google_health_ok?
      credential = AicooGoogleCredential.default
      return false unless credential&.refresh_token.present?

      critical_google_import_failures.zero?
    end

    def critical_google_import_failures
      return 0 unless defined?(GoogleApiImportRun)

      GoogleApiImportRun.where(business:, status: "failed", created_at: 24.hours.ago..).count
    end

    def no_recent_critical_error?
      recent_failed_runs.zero?
    end

    def recent_failed_runs
      business.auto_revision_run_logs.where(status: "failed", created_at: 24.hours.ago..).count
    end

    def previous_deploy_failed?
      return ActiveModel::Type::Boolean.new.cast(previous_deploy_failed) unless previous_deploy_failed.nil?

      business.auto_revision_run_logs.recent.where(deploy_result: "failed").exists?
    end
  end
end
