module Aicoo
  module Lovable
    class PipelineDiagnosis
      Component = Data.define(
        :key,
        :label,
        :level,
        :status_label,
        :connection_status,
        :cause,
        :required_setting,
        :settings_location,
        :fix_steps,
        :recheckable,
        :details
      ) do
        def healthy? = level == "healthy"
        def actionable? = level.in?(%w[settings error])
      end

      NextAction = Data.define(:text, :kind, :component)
      Result = Data.define(:level, :status_label, :components, :next_action) do
        def component(key)
          components.find { |row| row.key == key.to_sym }
        end
      end
      Summary = Data.define(:label, :level)

      LEVEL_LABELS = {
        "healthy" => "正常",
        "warning" => "注意",
        "settings" => "要設定",
        "error" => "エラー"
      }.freeze
      COMPONENT_STAGE_KEYS = {
        generate: :lovable,
        github_source_push: :github,
        webhook: :webhook,
        artifact_fetch: :github,
        publication_push: :github,
        cloudflare: :cloudflare,
        http_verification: :cloudflare,
        ga4: :ga4,
        gsc: :gsc,
        learning: :learning
      }.freeze
      GITHUB_ERROR_CODES = %w[
        repository_missing repository_mismatch branch_missing branch_mismatch
        github_permission_error artifact_fetch_failed result_import_failed
      ].freeze
      CLOUDFLARE_ERROR_CODES = %w[
        cloudflare_failed cloudflare_verification_timeout public_url_verification_timeout
      ].freeze

      def self.summary_for(
        landing_pages:,
        generation_runs_by_id:,
        ga4_status: nil,
        gsc_status: nil,
        cloudflare_configuration: Aicoo::CloudflarePages::Configuration.new
      )
        pages = Array(landing_pages)
        return Summary.new(label: "LP未登録", level: "warning") if pages.empty?

        runs = pages.filter_map do |page|
          generation_runs_by_id[page.metadata.to_h["lovable_generation_run_id"].to_i]
        end
        error_codes = runs.filter_map { |run| run.metadata.to_h["lovable_error_code"].presence }
        if error_codes.any? { |code| code.in?(GITHUB_ERROR_CODES) }
          return Summary.new(label: "GitHub設定不足", level: "error")
        end
        if error_codes.any? { |code| code.in?(CLOUDFLARE_ERROR_CODES) }
          return Summary.new(label: "Cloudflare設定不足", level: "error")
        end
        unless cloudflare_configuration.github_configured?
          return Summary.new(label: "GitHub設定不足", level: "settings")
        end
        unless cloudflare_configuration.cloudflare_api_configured?
          return Summary.new(label: "Cloudflare設定不足", level: "settings")
        end
        if google_reauthentication_required?(ga4_status) || google_reauthentication_required?(gsc_status)
          return Summary.new(label: "Google再認証必要", level: "settings")
        end
        unless google_configured?(ga4_status)
          return Summary.new(label: "GA4設定不足", level: "settings")
        end
        unless google_configured?(gsc_status)
          return Summary.new(label: "GSC設定不足", level: "settings")
        end
        return Summary.new(label: "Pipeline未開始", level: "warning") if runs.empty?

        learning_ready = runs.any? do |run|
          metadata = run.metadata.to_h
          metadata["learning_completed_at"].present? ||
            metadata["pipeline_status"].to_s.in?(%w[improvement_pending improvement_waiting completed])
        end
        return Summary.new(label: "Learning待ち", level: "warning") unless learning_ready

        Summary.new(label: "すべて正常", level: "healthy")
      end

      def self.component_for_stage(stage_key)
        COMPONENT_STAGE_KEYS[stage_key.to_sym]
      end

      def initialize(
        overview:,
        business:,
        landing_page:,
        generation_run:,
        analytics_site:,
        connection_statuses: {},
        webhook_configuration:,
        webhook_diagnostics:,
        cloudflare_configuration:,
        webhook_url: nil
      )
        @overview = overview
        @business = business
        @landing_page = landing_page
        @generation_run = generation_run
        @analytics_site = analytics_site
        @connection_statuses = connection_statuses.to_h.stringify_keys
        @webhook_configuration = webhook_configuration
        @webhook_diagnostics = webhook_diagnostics.to_h
        @cloudflare_configuration = cloudflare_configuration
        @webhook_url = webhook_url
      end

      def call
        components = [
          lovable_component,
          github_component,
          webhook_component,
          cloudflare_component,
          google_component("ga4"),
          google_component("gsc"),
          learning_component
        ]
        level = overall_level(components)
        Result.new(
          level:,
          status_label: LEVEL_LABELS.fetch(level),
          components:,
          next_action: next_action(components)
        )
      end

      private

      attr_reader :overview, :business, :landing_page, :generation_run, :analytics_site,
        :connection_statuses, :webhook_configuration, :webhook_diagnostics,
        :cloudflare_configuration, :webhook_url

      def metadata
        @metadata ||= generation_run&.metadata.to_h || {}
      end

      def landing_page_metadata
        @landing_page_metadata ||= landing_page&.metadata.to_h || {}
      end

      def error_code
        overview.error_code.to_s
      end

      def error_message
        overview.error_message.to_s
      end

      def diagnosis_snapshot(key)
        metadata.dig("pipeline_diagnosis", key.to_s).to_h
      end

      def lovable_component
        project_url = landing_page_metadata["lovable_project_url"].presence
        state = if overview.current_position < 3
          "Generate待ち"
        elsif overview.current_position == 3
          "Generate待ち"
        elsif source_commit_sha.present?
          "Push済み"
        else
          "Push待ち"
        end
        cause = case state
        when "Generate待ち" then "LovableでのGenerateがまだ完了していません。"
        when "Push待ち" then "Generate後のGitHub Pushを待っています。"
        else "Lovable成果物のPushを確認しました。"
        end
        level = state == "Push済み" ? "healthy" : "warning"
        component(
          :lovable,
          "Lovable",
          level:,
          cause:,
          required_setting: project_url.present? ? "設定済み" : "Lovable Project URL",
          settings_location: "LP詳細 → 設定 → Lovable Project URL",
          fix_steps: state == "Generate待ち" ? [ "Lovableを開く", "Generateを実行する" ] : [],
          details: {
            "Project URL" => project_url,
            "Repository" => source_repository,
            "Generate日時" => metadata["lovable_started_at"] || metadata["build_url_generated_at"],
            "最新Push" => metadata["github_webhook_received_at"],
            "状態" => state
          }
        )
      end

      def github_component
        snapshot = diagnosis_snapshot(:github)
        repo = source_repository
        branch = source_branch
        commit = source_commit_sha
        if overview.auto_recovering? && error_code.in?(GITHUB_ERROR_CODES)
          return component(
            :github,
            "GitHub",
            level: "healthy",
            cause: "AICOOが一時的なGitHub取得失敗を自動再試行しています。",
            details: github_details(repo, branch, commit)
          )
        end

        level, cause, required_setting, location, steps = github_problem(repo, branch, commit, snapshot)
        component(
          :github,
          "GitHub",
          level:,
          cause:,
          required_setting:,
          settings_location: location,
          fix_steps: steps,
          recheckable: level.in?(%w[settings error]),
          details: github_details(repo, branch, commit).merge(
            "Author" => metadata["source_commit_author"],
            "変更ファイル数" => metadata["source_changed_file_count"],
            "再確認日時" => snapshot["checked_at"]
          )
        )
      end

      def github_problem(repo, branch, commit, snapshot)
        if snapshot["ok"] == false && snapshot_matches?(snapshot, repository: repo, branch:)
          return github_snapshot_problem(snapshot)
        end
        if repo.blank?
          return [
            "settings",
            "Lovable成果物のGitHub Repositoryが未設定です。",
            "GitHub Repository URL",
            "LP詳細 → 設定 → GitHub Repository",
            [ "対象Repository URLを登録する", "Branchを確認する", "再確認を押す" ]
          ]
        end
        if branch.blank?
          return [
            "settings",
            "GitHub Branchが未設定です。",
            "Branch（通常はmain）",
            "LP詳細 → 設定 → Branch",
            [ "実在するBranch名を登録する", "再確認を押す" ]
          ]
        end
        case error_code
        when "github_permission_error"
          [
            "settings",
            "Fine-grained TokenのRepository accessに#{repository_name(repo)}が含まれていないか、Contents Read権限がありません。",
            "#{repository_name(repo)} / Contents Read",
            github_token_settings_location,
            [ "Fine-grained PATを開く", "Repository accessへ#{repository_name(repo)}を追加する", "Repository permissionsのContentsをReadにする", "再確認を押す" ]
          ]
        when "repository_missing", "repository_mismatch"
          [
            "error",
            "Repository #{repo.presence || '未設定'} が存在しないか、WebhookのRepositoryと登録値が一致しません。",
            "正しいGitHub Repository URL",
            "LP詳細 → 設定 → GitHub Repository",
            [ "GitHubでRepositoryが存在することを確認する", "LP設定のRepository URLを修正する", "再確認を押す" ]
          ]
        when "branch_missing", "branch_mismatch"
          [
            "error",
            "Branch #{branch.presence || '未設定'} が存在しないか、WebhookのBranchと登録値が一致しません。",
            "GitHubに存在するBranch",
            "LP詳細 → 設定 → Branch",
            [ "GitHubのBranch名を確認する", "LP設定のBranchを修正する", "再確認を押す" ]
          ]
        when "artifact_fetch_failed", "result_import_failed"
          [
            "error",
            error_message.presence || "GitHub成果物の取得に失敗しました。",
            "#{repository_name(repo)} / Contents Read",
            github_token_settings_location,
            [ "RepositoryとToken権限を確認する", "再確認を押す" ]
          ]
        else
          unless cloudflare_configuration.github_token.present?
            return [
              "settings",
              "AICOO_GITHUB_TOKENが未設定です。",
              "#{repository_name(repo)} Contents Read / aicoo-lp Contents Read and write",
              github_token_settings_location,
              [ "Fine-grained PATを作成する", "Repository accessへ対象Repositoryを追加する", "RenderのAICOO_GITHUB_TOKENへ保存する", "再確認を押す" ]
            ]
          end
          if commit.present?
            [ "healthy", "最新Commitを取得済みです。", nil, nil, [] ]
          else
            [ "warning", "GitHubの最新CommitまたはPushを待っています。", nil, nil, [] ]
          end
        end
      end

      def github_snapshot_problem(snapshot)
        cause = snapshot["cause"].presence || "GitHub接続を確認できませんでした。"
        required = snapshot["required_setting"].presence || "#{repository_name(source_repository)} / Contents Read"
        [
          snapshot["level"].presence || "error",
          cause,
          required,
          snapshot["settings_location"].presence || github_token_settings_location,
          Array(snapshot["fix_steps"])
        ]
      end

      def webhook_component
        snapshot = diagnosis_snapshot(:webhook)
        receipt = Array(metadata["github_webhook_receipts"]).last.to_h
        matching_global_receipt = webhook_diagnostics["repository"].to_s == normalized_repository
        if snapshot["ok"] == false
          level = snapshot["level"].presence || "error"
          cause = snapshot["cause"].presence || "Webhook接続を確認できませんでした。"
        elsif !webhook_configuration.configured?
          level = "settings"
          cause = "Webhook Secretが未設定です。"
        elsif webhook_diagnostics["last_status"].to_s.in?(%w[signature_mismatch webhook_secret_missing])
          level = "error"
          cause = webhook_diagnostics["last_status"] == "signature_mismatch" ?
            "GitHubとAICOOのWebhook Secretが一致していません。" :
            "AICOO側のWebhook Secretが未設定です。"
        elsif receipt.present? || matching_global_receipt
          level = "healthy"
          cause = "署名済みGitHub Pushを受信済みです。"
        elsif overview.current_position >= 4
          level = "settings"
          cause = "対象RepositoryからPushを受信していません。Webhook未登録、URL違い、またはSecret不一致の可能性があります。"
        else
          level = "warning"
          cause = "GitHub Push後にWebhook受信を確認します。"
        end

        component(
          :webhook,
          "Webhook",
          level:,
          cause:,
          required_setting: "Payload URL / application/json / Secret / Push event",
          settings_location: "GitHub Repository → Settings → Webhooks → Add webhook",
          fix_steps: [
            "Webhook URLをPayload URLへ登録する",
            "Content typeをapplication/jsonにする",
            "AICOOと同じSecretを登録する",
            "Push eventだけを選ぶ"
          ],
          recheckable: level.in?(%w[settings error]),
          details: {
            "Webhook URL" => webhook_url.presence || metadata["github_webhook_url"],
            "最終受信" => metadata["github_webhook_received_at"] || webhook_diagnostics["last_received_at"],
            "署名" => receipt["signature_status"] || webhook_diagnostics["signature_status"],
            "Repository" => receipt["repository"] || webhook_diagnostics["repository"],
            "Branch" => receipt["branch"] || webhook_diagnostics["branch"],
            "Payload" => receipt["payload_size_bytes"] || webhook_diagnostics["payload_size_bytes"]
          }
        )
      end

      def cloudflare_component
        snapshot = diagnosis_snapshot(:cloudflare)
        http_status = metadata.dig("publication", "http_status") || landing_page_metadata["cloudflare_http_status"]
        level, cause = if overview.auto_recovering? && error_code.in?(CLOUDFLARE_ERROR_CODES)
          [ "healthy", "AICOOがCloudflare公開状態を自動再確認しています。" ]
        elsif snapshot["ok"] == false
          [ snapshot["level"].presence || "error", snapshot["cause"].presence || "Cloudflare接続を確認できませんでした。" ]
        elsif cloudflare_configuration.account_id.blank?
          [ "settings", "CLOUDFLARE_ACCOUNT_IDが未設定です。" ]
        elsif cloudflare_configuration.api_token.blank?
          [ "settings", "CLOUDFLARE_API_TOKENが未設定です。" ]
        elsif cloudflare_configuration.project_name.blank?
          [ "settings", "Cloudflare Pages Projectが未設定です。" ]
        elsif error_code.in?(CLOUDFLARE_ERROR_CODES)
          [ "error", cloudflare_error_cause ]
        elsif http_status.to_i == 200
          [ "healthy", "Cloudflare Pagesの公開URLでHTTP 200を確認済みです。" ]
        else
          [ "warning", "Cloudflare Pagesへの公開またはHTTP確認を待っています。" ]
        end

        component(
          :cloudflare,
          "Cloudflare",
          level:,
          cause:,
          required_setting: "Account ID / API Token / Project #{cloudflare_configuration.project_name.presence || 'aicoo-lp'}",
          settings_location: "AICOO → Lovable接続 → Cloudflare Pages公開設定",
          fix_steps: [
            "Cloudflare Account IDを確認する",
            "Pages Read権限を持つTokenを設定する",
            "Project名が存在することを確認する",
            "再確認を押す"
          ],
          recheckable: level.in?(%w[settings error]),
          details: {
            "Project" => cloudflare_configuration.project_name,
            "Deploy" => landing_page_metadata["cloudflare_deploy_status"],
            "公開URL" => overview.public_url,
            "HTTP Status" => http_status,
            "最終確認" => landing_page_metadata["cloudflare_last_checked_at"],
            "再確認日時" => snapshot["checked_at"]
          }
        )
      end

      def google_component(source)
        status = connection_statuses[source]
        identifier = source == "ga4" ? analytics_site&.ga4_property_id : analytics_site&.gsc_site_url
        identifier ||= status&.identifier if status&.respond_to?(:identifier)
        reauthentication_required = self.class.send(:google_reauthentication_required?, status)
        configured = self.class.send(:google_configured?, status) || identifier.present?
        last_error = status&.last_error if status&.respond_to?(:last_error)
        level, cause = if reauthentication_required
          [ "settings", "Google OAuthの再認証が必要です。" ]
        elsif last_error.present?
          [ "error", last_error ]
        elsif configured
          [ "healthy", "#{source.upcase}はBusiness共通設定へ接続済みです。" ]
        else
          [ "settings", "#{source.upcase}のBusiness共通設定がありません。" ]
        end
        label = source.upcase
        component(
          source.to_sym,
          label,
          level:,
          cause:,
          required_setting: source == "ga4" ? "Google認証 / GA4 Property ID" : "Google認証 / GSC Site URL",
          settings_location: "Business → Google設定",
          fix_steps: reauthentication_required ?
            [ "Google再認証を開く", "GA4/GSCの権限を許可する" ] :
            [ "Business共通Google設定を開く", "#{label}の識別子を保存する" ],
          details: {
            (source == "ga4" ? "Property" : "Site") => identifier,
            "接続" => configured ? "接続済み" : "未接続",
            "最後の取得" => status&.last_fetched_at
          }
        )
      end

      def learning_component
        completed_at = metadata["learning_completed_at"]
        snapshot = metadata["learning_status"].presence
        ready = completed_at.present? || snapshot.present? || overview.completed?
        component(
          :learning,
          "Learning",
          level: ready ? "healthy" : "warning",
          cause: ready ? "Learning結果を保存済みです。" : "公開後のGA4・GSC計測を待っています。",
          details: {
            "状態" => snapshot || (ready ? "完了" : "待機"),
            "更新日時" => completed_at
          }
        )
      end

      def component(
        key,
        label,
        level:,
        cause:,
        required_setting: nil,
        settings_location: nil,
        fix_steps: [],
        recheckable: false,
        details: {}
      )
        Component.new(
          key:,
          label:,
          level:,
          status_label: LEVEL_LABELS.fetch(level),
          connection_status: level.in?(%w[healthy warning]) ? "OK" : "NG",
          cause:,
          required_setting:,
          settings_location:,
          fix_steps: Array(fix_steps),
          recheckable:,
          details: details.compact
        )
      end

      def overall_level(components)
        return "error" if components.any? { |row| row.level == "error" }
        return "settings" if components.any? { |row| row.level == "settings" }
        return "warning" if components.any? { |row| row.level == "warning" }

        "healthy"
      end

      def next_action(components)
        return NextAction.new(text: "現在AICOOが自動復旧中です。操作不要です。", kind: :none, component: nil) if overview.auto_recovering?
        return NextAction.new(text: "このLPの作成目的を選んで生成を開始してください。", kind: :create, component: nil) unless generation_run
        return NextAction.new(text: "LP戦略とPromptを確認して承認してください。", kind: :approve, component: nil) if overview.approval_waiting?
        return NextAction.new(text: "LovableでGenerateしてください。", kind: :generate, component: :lovable) if overview.current_position == 3

        current_component = self.class.component_for_stage(overview.current_stage.key)
        issue = components.find { |row| row.key == current_component && row.actionable? }
        issue ||= components.find(&:actionable?)
        if issue
          return NextAction.new(
            text: issue.fix_steps.first.presence || issue.cause,
            kind: issue.recheckable ? :recheck : :settings,
            component: issue.key
          )
        end
        return NextAction.new(text: "操作不要です。現在AICOOが処理中です。", kind: :none, component: nil) unless overview.completed?

        NextAction.new(text: "操作不要です。AICOOが次の改善を判断します。", kind: :none, component: nil)
      end

      def github_details(repo, branch, commit)
        {
          "Repository" => repo,
          "Branch" => branch,
          "Commit SHA" => commit,
          "Push日時" => metadata["github_webhook_received_at"],
          "最新Commit" => metadata["source_commit_url"].presence || commit
        }
      end

      def source_repository
        metadata["lovable_result_repository"].presence ||
          landing_page&.landing_page_repository_url
      end

      def source_branch
        metadata["lovable_result_branch"].presence ||
          landing_page&.landing_page_branch.presence ||
          "main"
      end

      def source_commit_sha
        metadata["source_commit_sha"].presence ||
          metadata["github_webhook_commit_sha"].presence ||
          metadata["lovable_last_synced_commit_sha"].presence
      end

      def normalized_repository
        GithubRepositoryIdentity.normalize(source_repository)
      end

      def repository_name(value)
        GithubRepositoryIdentity.normalize(value).to_s.split("/").last.presence || "対象Repository"
      end

      def snapshot_matches?(snapshot, repository:, branch:)
        snapshot["repository"].to_s == GithubRepositoryIdentity.normalize(repository).to_s &&
          snapshot["branch"].to_s == branch.to_s
      end

      def github_token_settings_location
        "GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Repository access"
      end

      def cloudflare_error_cause
        text = error_message.presence || landing_page_metadata["cloudflare_deploy_error"].to_s
        return "Cloudflare API Tokenが無効または期限切れです。" if text.match?(/unauthor|forbidden|token|authentication/i)
        return "Cloudflare Pages Projectが存在しないか、Project名が一致しません。" if text.match?(/project|not found|404/i)
        return "Cloudflare公開URLのHTTP 200を確認できませんでした。" if error_code == "public_url_verification_timeout"

        text.presence || "Cloudflare PagesのDeployに失敗しました。"
      end

      class << self
        private

        def google_reauthentication_required?(status)
          status&.respond_to?(:reauthentication_required) && status.reauthentication_required
        end

        def google_configured?(status)
          status&.respond_to?(:configured?) && status.configured?
        end
      end
    end
  end
end
