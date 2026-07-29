require "test_helper"

module Aicoo
  module Lovable
    class PipelineOverviewTest < ActiveSupport::TestCase
      Run = Struct.new(:metadata, :error_message, :created_at)
      Task = Struct.new(:status, :approved_at, :metadata)
      Business = Struct.new(:name, :metadata)
      AnalyticsSite = Struct.new(:ga4_property_id, :gsc_site_url, :last_ga4_fetch_at, :last_gsc_fetch_at)
      Snapshot = Struct.new(:id, :payload, :captured_at)
      CloudflareConfiguration = Struct.new(:project_name)
      LandingPage = Struct.new(:metadata, :created_at) do
        def landing_page_url
          metadata.to_h["lp_url"]
        end
      end

      test "maps webhook processing to the sixth of thirteen user stages" do
        overview = build_overview(
          status: "artifact_fetching",
          metadata: { "github_webhook_received_at" => "2026-07-29T12:00:00+09:00" }
        )

        assert_equal 13, overview.stages.size
        assert_equal 6, overview.current_position
        assert_equal "成果物取得", overview.current_label
        assert_equal "静的build", overview.next_label
        assert_equal "なし", overview.user_operation
        assert_equal "completed", overview.stages[4].status
        assert_equal "current", overview.stages[5].status
        assert_equal "実行中", overview.stage_status_label(overview.current_stage)
      end

      test "labels an LP without a generation run as not started" do
        overview = PipelineOverview.new(generation_run: nil, landing_page: nil, task: nil)

        assert_equal "未開始", overview.headline_status
        assert_equal "未開始", overview.stage_status_label(overview.current_stage)
        assert_not overview.refresh?
      end

      test "keeps owner approval as the only action before lovable launch" do
        task = Task.new("waiting_approval", nil, {})
        overview = build_overview(status: "prompt_ready", task:)

        assert_equal 2, overview.current_position
        assert overview.approval_waiting?
        assert_equal "承認待ち", overview.headline_status
        assert_equal "承認待ち", overview.stage_status_label(overview.current_stage)
        assert_includes overview.next_action_text, "承認"
      end

      test "requires no owner action while waiting for the github push" do
        overview = build_overview(status: "github_webhook_waiting")

        assert_equal 4, overview.current_position
        assert_equal "実行中", overview.headline_status
        assert_equal "なし", overview.user_operation
        assert_includes overview.next_action_text, "操作不要"
      end

      test "marks published and analyzed pipeline complete with history" do
        overview = build_overview(
          status: "improvement_waiting",
          metadata: {
            "publication" => {
              "commit_sha" => "abc123",
              "production_url" => "https://aicoo-lp.pages.dev/test/",
              "published_at" => "2026-07-29T12:03:00+09:00"
            },
            "measurement_sources" => { "ga4" => "available", "gsc" => "available" },
            "measurement_checked_at" => "2026-07-29T12:05:00+09:00",
            "learning_completed_at" => "2026-07-29T12:06:00+09:00"
          }
        )

        assert overview.completed?
        assert_equal 13, overview.current_position
        assert overview.stages.all? { |stage| stage.status == "completed" }
        assert_equal "abc123", overview.commit_sha
        assert_equal "https://aicoo-lp.pages.dev/test/", overview.public_url
        assert overview.history.any? { |entry| entry.label == "Learning完了" }
      end

      test "keeps failure at its stage and provides recovery guidance" do
        overview = build_overview(
          status: "waiting_manual_fix",
          metadata: {
            "lovable_error_code" => "static_validation_failed",
            "lovable_error_message" => "unsafe script"
          }
        )

        assert overview.failed?
        assert_equal 7, overview.current_position
        assert_equal "failed", overview.stages[6].status
        assert_equal "静的build", overview.current_label
        assert_includes overview.user_operation, "Lovable成果物"
        assert_not overview.refresh?
      end

      test "keeps a transient importer failure in automatic recovery without owner notification" do
        overview = build_overview(
          status: "github_webhook_waiting",
          metadata: {
            "lovable_error_code" => "artifact_fetch_failed",
            "lovable_error_message" => "timeout",
            "pipeline_recovery_status" => "retrying",
            "pipeline_retry_count" => 1,
            "pipeline_retry_limit" => 3
          }
        )

        assert_not overview.failed?
        assert overview.auto_recovering?
        assert overview.refresh?
        assert_equal 6, overview.current_position
        assert_equal "recovering", overview.current_stage.status
        assert_equal "自動復旧中", overview.headline_status
        assert_equal "なし", overview.user_operation
        assert_includes overview.next_action_text, "操作は不要"
      end

      test "exposes stored pipeline diagnostics and business common measurement settings" do
        measured_at = Time.zone.parse("2026-07-29 12:08:00")
        business = Business.new("Explorer Business", { "lp_ga4_measurement_id" => "G-EXPLORER" })
        analytics_site = AnalyticsSite.new(
          "properties/123",
          "sc-domain:lp.example.com",
          measured_at,
          measured_at
        )
        snapshot = Snapshot.new(
          91,
          {
            "evaluation" => { "improvement_candidate_count" => 2 },
            "learning" => {
              "status" => "evaluated",
              "improvement_type" => "cta_improvement",
              "success" => true
            }
          },
          measured_at
        )
        overview = build_overview(
          status: "improvement_waiting",
          metadata: {
            "lovable_result_repository" => "https://github.com/example/lovable-output",
            "lovable_result_branch" => "main",
            "github_webhook_commit_sha" => "source123",
            "github_webhook_receipts" => [ {
              "repository" => "example/lovable-output",
              "branch" => "main",
              "commit_sha" => "source123",
              "signature_status" => "verified",
              "payload_size_bytes" => 2_048,
              "changed_file_count" => 2,
              "changed_paths" => %w[index.html app.css]
            } ],
            "artifact_fetched_file_count" => 3,
            "artifact_file_counts" => { "html" => 1, "css" => 1, "javascript" => 1, "images" => 0 },
            "artifact_excluded_paths" => [ ".env" ],
            "static_build_generated_file_count" => 3,
            "static_build_log" => [ "Static build succeeded" ],
            "publication" => {
              "repository_url" => "https://github.com/example/aicoo-lp",
              "branch" => "main",
              "commit_sha" => "published123",
              "changed_file_count" => 3,
              "changed_paths" => %w[public/lp/index.html public/lp/app.css public/lp/app.js],
              "production_url" => "https://aicoo-lp.pages.dev/lp/",
              "http_status" => 200,
              "content_type" => "text/html"
            },
            "measurement_sources" => { "ga4" => "available", "gsc" => "available" },
            "measurement_checked_at" => measured_at.iso8601,
            "learning_completed_at" => measured_at.iso8601
          },
          business:,
          analytics_site:,
          snapshot:
        )

        github = overview.stages.find { |stage| stage.key == :github_source_push }.diagnostics.index_by(&:label)
        assert_equal 2, github.fetch("変更ファイル数").value
        assert_equal %w[index.html app.css], github.fetch("変更ファイル一覧").value

        ga4 = overview.stages.find { |stage| stage.key == :ga4 }.diagnostics.index_by(&:label)
        assert_equal "Business共通設定（Explorer Business）", ga4.fetch("設定元").value
        assert_equal "properties/123", ga4.fetch("Property").value
        assert_equal "G-EXPLORER", ga4.fetch("Measurement ID").value

        learning = overview.stages.find { |stage| stage.key == :learning }.diagnostics.index_by(&:label)
        assert_equal "#91", learning.fetch("Snapshot").value
        assert_equal 2, learning.fetch("改善候補数").value
        assert_equal "cta_improvement（成功）", learning.fetch("勝ちパターン").value
      end

      test "renders a business common setting label for binary encoded Japanese names" do
        business_name = "AI受付".dup.force_encoding(Encoding::ASCII_8BIT)
        overview = build_overview(
          status: "ga4_pending",
          business: Business.new(business_name, {})
        )

        ga4 = overview.stages.find { |stage| stage.key == :ga4 }.diagnostics.index_by(&:label)
        landing_page = overview.stages.find { |stage| stage.key == :landing_page }.diagnostics.index_by(&:label)

        assert_equal "Business共通設定（AI受付）", ga4.fetch("設定元").value
        assert_equal "AI受付", landing_page.fetch("Business").value
      end

      test "does not mark missing measurement sources complete" do
        overview = build_overview(
          status: "improvement_waiting",
          metadata: {
            "measurement_sources" => { "ga4" => "available", "gsc" => "waiting" },
            "measurement_checked_at" => "2026-07-29T12:05:00+09:00"
          }
        )

        assert_not overview.completed?
        assert_equal 12, overview.current_position
        assert_equal "GSC", overview.current_label
        assert overview.refresh?
      end

      test "summarizes published processing and failed landing pages without persistence" do
        published = fake_page(
          "lp_public_status" => "published",
          "cloudflare_deploy_status" => "deployed",
          "cloudflare_url" => "https://example.com/published/"
        )
        processing = fake_page(
          "lovable_generation_run_id" => 1,
          "planning_status" => "artifact_fetching"
        )
        failed = fake_page(
          "lovable_generation_run_id" => 2,
          "sync_status" => "failed"
        )

        assert_equal(
          { published_count: 1, processing_count: 1, failed_count: 1 },
          PipelineOverview.summary_for([ published, processing, failed ])
        )
      end

      private

      def build_overview(status:, metadata: {}, task: nil, business: nil, analytics_site: nil, snapshot: nil)
        run_metadata = {
          "pipeline_status" => status,
          "pipeline" => "lovable",
          "publication" => {}
        }.deep_merge(metadata)
        PipelineOverview.new(
          generation_run: Run.new(run_metadata, nil, Time.zone.parse("2026-07-29 11:55:00")),
          landing_page: LandingPage.new({}, Time.zone.parse("2026-07-29 11:50:00")),
          task: task,
          business:,
          analytics_site:,
          learning_snapshot: snapshot,
          cloudflare_configuration: CloudflareConfiguration.new("aicoo-lp"),
          webhook_url: "https://aicoo.example.com/webhooks/github"
        )
      end

      def fake_page(metadata)
        Class.new do
          attr_reader :metadata

          def initialize(values)
            @metadata = values
          end

          def cloudflare_published?
            metadata["lp_public_status"] == "published" &&
              metadata["cloudflare_deploy_status"] == "deployed" &&
              metadata["cloudflare_url"].present?
          end
        end.new(metadata)
      end
    end
  end
end
