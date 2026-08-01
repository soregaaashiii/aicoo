module Aicoo
  module Lovable
    class PipelineRechecker
      Result = Data.define(
        :component,
        :ok,
        :level,
        :code,
        :cause,
        :required_setting,
        :settings_location,
        :fix_steps,
        :details
      )

      def initialize(
        cloudflare_configuration: Aicoo::CloudflarePages::Configuration.new,
        github_client_class: Aicoo::CloudflarePages::GithubRepositoryClient,
        cloudflare_verifier: nil,
        webhook_configuration: Aicoo::Lovable::GithubWebhookConfiguration.new
      )
        @cloudflare_configuration = cloudflare_configuration
        @github_client_class = github_client_class
        @cloudflare_verifier = cloudflare_verifier ||
          Aicoo::CloudflarePages::DeploymentVerifier.new(configuration: cloudflare_configuration)
        @webhook_configuration = webhook_configuration
      end

      def call(component:, landing_page:, generation_run:)
        case component.to_s
        when "github" then check_github(landing_page, generation_run)
        when "cloudflare" then check_cloudflare(landing_page)
        when "webhook" then check_webhook(generation_run)
        else
          failure(component, "unsupported_component", "この工程は再確認対象ではありません。")
        end
      end

      private

      attr_reader :cloudflare_configuration, :github_client_class, :cloudflare_verifier,
        :webhook_configuration

      def check_github(landing_page, generation_run)
        metadata = generation_run.metadata.to_h
        repository = metadata["lovable_result_repository"].presence ||
          landing_page&.landing_page_repository_url
        branch = metadata["lovable_result_branch"].presence ||
          landing_page&.landing_page_branch.presence ||
          "main"
        return github_failure("repository_missing", "GitHub Repositoryが未設定です。", repository:, branch:) if repository.blank?
        return github_failure("branch_missing", "GitHub Branchが未設定です。", repository:, branch:) if branch.blank?
        unless cloudflare_configuration.github_token.present?
          return github_failure(
            "github_token_missing",
            "AICOO_GITHUB_TOKENが未設定です。",
            repository:,
            branch:
          )
        end

        commit = github_client_class.new(
          repository_url: repository,
          branch:,
          token: cloudflare_configuration.github_token
        ).latest_commit!
        success(
          :github,
          "GitHub RepositoryとBranchへ接続できました。",
          {
            "repository" => GithubRepositoryIdentity.normalize(repository),
            "branch" => branch,
            "commit_sha" => commit.commit_sha,
            "commit_url" => commit.commit_url,
            "committed_at" => commit.committed_at,
            "author" => commit.author,
            "changed_file_count" => commit.changed_paths.size
          }
        )
      rescue ArgumentError => e
        code = github_error_code(e.message, generation_run)
        github_failure(code, github_error_cause(code, repository, branch, e.message), repository:, branch:)
      rescue StandardError => e
        github_failure(
          "github_connection_failed",
          "GitHub接続確認に失敗しました: #{e.message}",
          repository:,
          branch:
        )
      end

      def check_cloudflare(landing_page)
        supports_business = cloudflare_verifier.method(:check_connection).parameters.any? do |_kind, name|
          name == :business
        end
        result = if supports_business
          cloudflare_verifier.check_connection(business: landing_page&.business)
        else
          cloudflare_verifier.check_connection
        end
        return success(:cloudflare, result.message, {
          "project_name" => result.project_name,
          "http_status" => result.http_status
        }) if result.ok

        failure(
          :cloudflare,
          result.code,
          result.message,
          required_setting: "AICOO全体Cloudflare接続 / Pages Project",
          settings_location: "AICOO → 全体設定 → Cloudflare",
          fix_steps: [ "Cloudflare全体設定を確認する", "BusinessのPages Projectを確認する", "再確認を押す" ],
          details: {
            "project_name" => result.project_name,
            "http_status" => result.http_status
          }
        )
      end

      def check_webhook(generation_run)
        diagnostics = webhook_configuration.diagnostics
        receipt = Array(generation_run.metadata.to_h["github_webhook_receipts"]).last.to_h
        unless webhook_configuration.configured?
          return failure(
            :webhook,
            "webhook_secret_missing",
            "Webhook Secretが未設定です。",
            required_setting: "Payload URL / Secret / Push event",
            settings_location: "GitHub Repository → Settings → Webhooks",
            fix_steps: webhook_fix_steps
          )
        end
        if diagnostics["last_status"] == "signature_mismatch"
          return failure(
            :webhook,
            "signature_mismatch",
            "GitHubとAICOOのWebhook Secretが一致していません。",
            required_setting: "AICOOと同じWebhook Secret",
            settings_location: "GitHub Repository → Settings → Webhooks",
            fix_steps: webhook_fix_steps
          )
        end
        if receipt.blank?
          return failure(
            :webhook,
            "webhook_not_received",
            "対象RepositoryからPushを受信していません。Webhook未登録またはPush未送信の可能性があります。",
            required_setting: "Payload URL / application/json / Secret / Push event",
            settings_location: "GitHub Repository → Settings → Webhooks → Add webhook",
            fix_steps: webhook_fix_steps
          )
        end

        success(:webhook, "署名済みGitHub Pushを受信済みです。", {
          "repository" => receipt["repository"],
          "branch" => receipt["branch"],
          "commit_sha" => receipt["commit_sha"],
          "received_at" => receipt["received_at"]
        })
      end

      def success(component, cause, details)
        Result.new(
          component: component.to_s,
          ok: true,
          level: "healthy",
          code: "ok",
          cause:,
          required_setting: nil,
          settings_location: nil,
          fix_steps: [],
          details:
        )
      end

      def failure(
        component,
        code,
        cause,
        required_setting: nil,
        settings_location: nil,
        fix_steps: [],
        details: {}
      )
        settings_codes = %w[
          repository_missing branch_missing github_token_missing
          account_id_missing api_token_missing project_missing
          webhook_secret_missing webhook_not_received
        ]
        Result.new(
          component: component.to_s,
          ok: false,
          level: code.to_s.in?(settings_codes) ? "settings" : "error",
          code:,
          cause:,
          required_setting:,
          settings_location:,
          fix_steps:,
          details:
        )
      end

      def github_failure(code, cause, repository:, branch:)
        failure(
          :github,
          code,
          cause,
          required_setting: "#{GithubRepositoryIdentity.normalize(repository).to_s.split('/').last.presence || '対象Repository'} / Contents Read",
          settings_location: "GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Repository access",
          fix_steps: [
            "Fine-grained PATのRepository accessを確認する",
            "対象RepositoryへContents Readを許可する",
            "RenderのAICOO_GITHUB_TOKENを更新する",
            "再確認を押す"
          ],
          details: {
            "repository" => GithubRepositoryIdentity.normalize(repository),
            "branch" => branch
          }
        )
      end

      def github_error_code(message, generation_run)
        existing = generation_run.metadata.to_h["lovable_error_code"].to_s
        return existing if existing.in?(%w[repository_missing repository_mismatch branch_missing branch_mismatch github_permission_error])
        return "branch_missing" if message.match?(/branch|ref/i)
        return "github_permission_error" if message.match?(/token|permission|access|401|403/i)

        "repository_missing"
      end

      def github_error_cause(code, repository, branch, original)
        case code
        when "github_permission_error"
          "Fine-grained TokenのRepository accessに#{GithubRepositoryIdentity.normalize(repository)}が含まれていないか、Contents Read権限がありません。"
        when "branch_missing", "branch_mismatch"
          "Branch #{branch} が存在しないか、登録値と一致しません。"
        when "repository_missing", "repository_mismatch"
          "Repository #{repository} が存在しないか、登録値と一致しません。"
        else
          original
        end
      end

      def webhook_fix_steps
        [
          "Webhook URLをPayload URLへ登録する",
          "Content typeをapplication/jsonにする",
          "AICOOと同じSecretを登録する",
          "Push eventだけを選ぶ"
        ]
      end
    end
  end
end
