require "test_helper"

module Aicoo
  module Lovable
    class PipelineDiagnosisTest < ActiveSupport::TestCase
      Run = Struct.new(:metadata, :error_message, :created_at, :status)
      Business = Struct.new(:name, :metadata)
      AnalyticsSite = Struct.new(:ga4_property_id, :gsc_site_url)
      WebhookConfiguration = Struct.new(:configured?)
      CloudflareConfiguration = Struct.new(
        :account_id,
        :api_token,
        :project_name,
        :github_token
      ) do
        def github_configured?
          github_token.present?
        end

        def cloudflare_api_configured?
          account_id.present? && api_token.present? && project_name.present?
        end
      end
      ConnectionStatus = Struct.new(
        :configured,
        :reauthentication_required,
        :identifier,
        :last_fetched_at,
        :last_error
      ) do
        def configured? = configured
      end
      LandingPage = Struct.new(:metadata, :created_at) do
        def landing_page_repository_url = metadata["repository"]
        def landing_page_branch = metadata["branch"].presence || "main"
        def landing_page_url = metadata["lp_url"]
      end

      test "diagnoses a fine grained token without source repository access" do
        diagnosis = build_diagnosis(
          status: "github_webhook_waiting",
          error_code: "github_permission_error",
          error_message: "GitHub Repository example/voice-analysis-pro へアクセスできません。"
        )

        github = diagnosis.component(:github)
        assert_equal "settings", github.level
        assert_equal "NG", github.connection_status
        assert_includes github.cause, "voice-analysis-pro"
        assert_includes github.cause, "Contents Read"
        assert_includes github.settings_location, "Fine-grained"
        assert_equal :recheck, diagnosis.next_action.kind
      end

      test "distinguishes missing repository and missing branch" do
        missing_repository = build_diagnosis(
          status: "github_webhook_waiting",
          error_code: "repository_missing",
          landing_page_metadata: { "branch" => "main" }
        )
        missing_branch = build_diagnosis(
          status: "github_webhook_waiting",
          error_code: "branch_missing",
          landing_page_metadata: {
            "repository" => "https://github.com/example/lp",
            "branch" => ""
          },
          run_metadata: { "lovable_result_branch" => "" }
        )

        assert_includes missing_repository.component(:github).cause, "Repository"
        assert_includes missing_branch.component(:github).cause, "Branch"
      end

      test "diagnoses a missing cloudflare token and project settings" do
        configuration = CloudflareConfiguration.new("account", nil, "aicoo-lp", "github-token")
        diagnosis = build_diagnosis(
          status: "cloudflare_waiting",
          cloudflare_configuration: configuration
        )

        cloudflare = diagnosis.component(:cloudflare)
        assert_equal "settings", cloudflare.level
        assert_equal "AICOO全体のCloudflare認証が未設定です。", cloudflare.cause
        assert_includes cloudflare.required_setting, "AICOO全体Cloudflare接続"
      end

      test "diagnoses an unregistered or unreceived webhook" do
        diagnosis = build_diagnosis(
          status: "github_webhook_waiting",
          webhook_configuration: WebhookConfiguration.new(true),
          webhook_diagnostics: {}
        )

        webhook = diagnosis.component(:webhook)
        assert_equal "settings", webhook.level
        assert_includes webhook.cause, "Webhook未登録"
        assert_includes webhook.settings_location, "Settings"
      end

      test "reports a successful github commit and cloudflare HTTP 200" do
        diagnosis = build_diagnosis(
          status: "measurement_waiting",
          run_metadata: {
            "source_commit_sha" => "source123",
            "source_commit_url" => "https://github.com/example/lp/commit/source123",
            "source_commit_author" => "owner",
            "source_changed_file_count" => 4,
            "publication" => {
              "production_url" => "https://aicoo-lp.pages.dev/test/",
              "http_status" => 200
            }
          },
          landing_page_metadata: {
            "repository" => "https://github.com/example/lp",
            "branch" => "main",
            "cloudflare_http_status" => 200,
            "cloudflare_deploy_status" => "deployed"
          }
        )

        github = diagnosis.component(:github)
        cloudflare = diagnosis.component(:cloudflare)
        assert_equal "healthy", github.level
        assert_equal "source123", github.details["Commit SHA"]
        assert_equal "owner", github.details["Author"]
        assert_equal "healthy", cloudflare.level
        assert_equal 200, cloudflare.details["HTTP Status"]
      end

      test "requires google reauthentication from the business common setting" do
        ga4_status = ConnectionStatus.new(false, true, "properties/123", nil, nil)
        gsc_status = ConnectionStatus.new(true, false, "sc-domain:example.com", Time.current, nil)
        diagnosis = build_diagnosis(
          status: "ga4_pending",
          connection_statuses: { "ga4" => ga4_status, "gsc" => gsc_status }
        )

        ga4 = diagnosis.component(:ga4)
        assert_equal "settings", ga4.level
        assert_equal "Google OAuthの再認証が必要です。", ga4.cause
        assert_equal "Business → Google設定", ga4.settings_location
      end

      test "shows the publication notice instead of blocking a published LP without GA4" do
        diagnosis = build_diagnosis(
          status: "completed",
          run_metadata: {
            "ga4_measurement_warning" => StaticArtifactValidator::GA4_MISSING_WARNING,
            "static_validation_warnings" => [ StaticArtifactValidator::GA4_MISSING_WARNING ],
            "publication" => {
              "production_url" => "https://aicoo-lp.pages.dev/test/",
              "http_status" => 200
            }
          },
          connection_statuses: {
            "ga4" => ConnectionStatus.new(false, false, nil, nil, nil),
            "gsc" => ConnectionStatus.new(true, false, "sc-domain:example.com", Time.current, nil)
          }
        )

        assert_equal "warning", diagnosis.component(:ga4).level
        assert_equal StaticArtifactValidator::GA4_MISSING_WARNING, diagnosis.component(:ga4).cause
        assert_equal StaticArtifactValidator::GA4_PUBLICATION_NOTICE, diagnosis.next_action.text
        assert_equal :none, diagnosis.next_action.kind
      end

      test "does not surface an owner action while automatic recovery is running" do
        diagnosis = build_diagnosis(
          status: "github_webhook_waiting",
          error_code: "artifact_fetch_failed",
          run_metadata: { "pipeline_recovery_status" => "retrying" }
        )

        assert_equal :none, diagnosis.next_action.kind
        assert_includes diagnosis.next_action.text, "操作不要"
        assert_equal "healthy", diagnosis.component(:github).level
      end

      test "summarizes the single blocking pipeline setting for business index" do
        page = LandingPage.new(
          {
            "lovable_generation_run_id" => 7,
            "repository" => "https://github.com/example/lp",
            "branch" => "main"
          },
          Time.current
        )
        run = Run.new(
          {
            "lovable_error_code" => "github_permission_error",
            "pipeline_status" => "github_webhook_waiting"
          },
          "permission denied",
          Time.current,
          "failed"
        )
        connected = ConnectionStatus.new(true, false, "configured", Time.current, nil)

        summary = PipelineDiagnosis.summary_for(
          landing_pages: [ page ],
          generation_runs_by_id: { 7 => run },
          ga4_status: connected,
          gsc_status: connected,
          cloudflare_configuration: default_cloudflare_configuration
        )

        assert_equal "GitHub設定不足", summary.label
        assert_equal "error", summary.level
      end

      private

      def build_diagnosis(
        status:,
        error_code: nil,
        error_message: nil,
        run_metadata: {},
        landing_page_metadata: {},
        connection_statuses: nil,
        webhook_configuration: WebhookConfiguration.new(true),
        webhook_diagnostics: {
          "last_status" => "accepted",
          "repository" => "example/lp"
        },
        cloudflare_configuration: default_cloudflare_configuration
      )
        run_values = {
          "pipeline" => "lovable",
          "pipeline_status" => status,
          "lovable_result_repository" => "https://github.com/example/lp",
          "lovable_result_branch" => "main",
          "publication" => {}
        }.deep_merge(run_metadata)
        run_values["lovable_error_code"] = error_code if error_code
        run_values["lovable_error_message"] = error_message if error_message
        run = Run.new(run_values, error_message, Time.current, error_code ? "failed" : "succeeded")
        landing_page = LandingPage.new(
          {
            "repository" => "https://github.com/example/lp",
            "branch" => "main",
            "lovable_project_url" => "https://lovable.dev/projects/test"
          }.merge(landing_page_metadata),
          Time.current
        )
        overview = PipelineOverview.new(
          generation_run: run,
          landing_page:,
          task: nil,
          business: Business.new("Diagnosis Business", {}),
          cloudflare_configuration:
        )
        statuses = connection_statuses || {
          "ga4" => ConnectionStatus.new(true, false, "properties/123", Time.current, nil),
          "gsc" => ConnectionStatus.new(true, false, "sc-domain:example.com", Time.current, nil)
        }
        PipelineDiagnosis.new(
          overview:,
          business: Business.new("Diagnosis Business", {}),
          landing_page:,
          generation_run: run,
          analytics_site: AnalyticsSite.new("properties/123", "sc-domain:example.com"),
          connection_statuses: statuses,
          webhook_configuration:,
          webhook_diagnostics:,
          cloudflare_configuration:
        ).call
      end

      def default_cloudflare_configuration
        CloudflareConfiguration.new("account", "cloudflare-token", "aicoo-lp", "github-token")
      end
    end
  end
end
