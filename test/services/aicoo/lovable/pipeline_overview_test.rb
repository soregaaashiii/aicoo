require "test_helper"

module Aicoo
  module Lovable
    class PipelineOverviewTest < ActiveSupport::TestCase
      Run = Struct.new(:metadata, :error_message, :created_at)
      Task = Struct.new(:status, :approved_at, :metadata)
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

      test "keeps owner approval as the only action before lovable launch" do
        task = Task.new("waiting_approval", nil, {})
        overview = build_overview(status: "prompt_ready", task:)

        assert_equal 2, overview.current_position
        assert overview.approval_waiting?
        assert_equal "承認待ち", overview.headline_status
        assert_equal "承認待ち", overview.stage_status_label(overview.current_stage)
        assert_includes overview.next_action_text, "承認"
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

      def build_overview(status:, metadata: {}, task: nil)
        run_metadata = {
          "pipeline_status" => status,
          "pipeline" => "lovable",
          "publication" => {}
        }.deep_merge(metadata)
        PipelineOverview.new(
          generation_run: Run.new(run_metadata, nil, Time.zone.parse("2026-07-29 11:55:00")),
          landing_page: LandingPage.new({}, Time.zone.parse("2026-07-29 11:50:00")),
          task: task
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
