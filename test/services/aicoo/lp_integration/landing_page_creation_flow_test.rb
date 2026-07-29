require "test_helper"

module Aicoo
  module LpIntegration
    class LandingPageCreationFlowTest < ActiveSupport::TestCase
      setup do
        @business = Business.create!(
          name: "AI受付",
          description: "電話対応をAIで自動化するサービス",
          status: "building",
          business_type: "saas"
        )
        @campaign = @business.business_campaigns.create!(
          name: "Google Ads",
          campaign_type: "google_ads",
          status: "active"
        )
      end

      test "purpose only creates strategy prompt candidate and waiting approval task" do
        result = nil
        assert_difference [
          "BusinessPrototype.count",
          "AicooLabGenerationRun.count",
          "ActionCandidate.count",
          "AutoRevisionTask.count"
        ], 1 do
          result = LandingPageCreationFlow.new(
            business: @business,
            campaign: @campaign,
            attributes: { purpose: "google_ads" },
            strategy_builder_class: fake_strategy_builder
          ).call
        end

        landing_page = result.landing_page.reload
        assert_equal @campaign, landing_page.business_campaign
        assert_equal "testing", landing_page.landing_page_public_status
        assert_equal "Google広告", landing_page.metadata.to_h["creation_purpose_label"]
        assert_equal "waiting_approval", landing_page.metadata.to_h["planning_status"]
        assert_equal 48_000, landing_page.metadata.to_h["expected_profit_yen"]

        run = result.generation_run.reload
        assert_equal landing_page.id, run.metadata.to_h["landing_page_prototype_id"]
        assert_equal "prompt_ready", run.metadata.to_h["pipeline_status"]
        assert_includes run.prompt, "資料請求する"
        assert_includes run.prompt, "ファーストビュー"

        assert_equal "build_lp", result.candidate.action_type
        assert_equal "lovable_generation", result.candidate.execution_mode
        assert_equal "waiting_approval", result.task.status
        assert_equal "lovable_pending", result.task.metadata.to_h["pipeline_stage"]
        assert_equal false, result.task.metadata.to_h["auto_deploy_enabled"]
        assert_equal "cloudflare_pages", result.task.metadata.to_h["target_deploy_target"]
      end

      test "approval creates one official Build URL and keeps retry idempotent" do
        result = LandingPageCreationFlow.new(
          business: @business,
          campaign: @campaign,
          attributes: { purpose: "google_ads" },
          strategy_builder_class: fake_strategy_builder
        ).call

        assert_nil result.generation_run.metadata.to_h["build_url"]
        assert result.task.approve!
        first_url = result.generation_run.reload.metadata.to_h["build_url"]
        assert_includes first_url, "https://lovable.dev/?autosubmit=true#prompt="
        assert_equal "lovable_handoff_ready", result.generation_run.metadata.to_h["pipeline_status"]
        assert_equal "approved", result.task.reload.status

        assert result.task.approve!
        assert_equal first_url, result.generation_run.reload.metadata.to_h["build_url"]
      end

      test "starts an existing unstarted landing page without creating a duplicate" do
        landing_page = LandingPageRegistry.new(business: @business).save!(
          campaign_id: @campaign.id,
          name: "既存LP",
          source_type: "manual",
          public_status: "testing"
        )

        result = nil
        assert_no_difference("BusinessPrototype.count") do
          result = LandingPageCreationFlow.new(
            business: @business,
            campaign: @campaign,
            landing_page:,
            attributes: { purpose: "google_ads" },
            strategy_builder_class: fake_strategy_builder
          ).call
        end

        assert_equal landing_page, result.landing_page
        assert_equal "waiting_approval", landing_page.reload.metadata["planning_status"]
        assert_equal landing_page.id, result.generation_run.metadata["landing_page_prototype_id"]
        assert_equal "waiting_approval", result.task.status
      end

      test "imports validated static result once and reuses the published commit on retry" do
        @business.update!(metadata: @business.metadata.to_h.merge("lp_ga4_measurement_id" => "G-ABC123"))
        @business.business_services.create!(
          name: "AI受付 Service",
          status: "production",
          url: "https://service.example.com"
        )
        flow = LandingPageCreationFlow.new(
          business: @business,
          campaign: @campaign,
          attributes: { purpose: "google_ads" },
          strategy_builder_class: fake_strategy_builder
        ).call
        flow.landing_page.update!(metadata: flow.landing_page.metadata.to_h.merge("ga4_page_path" => "/ai-reception"))
        flow.task.approve!
        Aicoo::Lovable::LandingPagePipeline.new.register_result!(
          business: @business,
          generation_run: flow.generation_run,
          project_url: "https://lovable.dev/projects/project-123",
          result_repository: "https://github.com/example/lovable-result",
          result_branch: "main"
        )

        source_client_class = fake_source_client_class
        publisher = FakePublisher.new
        importer = Aicoo::Lovable::ResultRepositoryImporter.new(
          source_client_class:,
          publisher:,
          configuration: Aicoo::CloudflarePages::Configuration.new(
            env: {
              "AICOO_GITHUB_TOKEN" => "token",
              "CLOUDFLARE_PAGES_PRODUCTION_URL" => "https://aicoo-lp.pages.dev"
            }
          )
        )

        first = importer.call(generation_run: flow.generation_run)
        second = importer.call(generation_run: flow.generation_run.reload)

        assert_equal false, first.idempotent
        assert_equal true, second.idempotent
        assert_equal 1, publisher.calls
        assert_equal "cloudflare_waiting", flow.generation_run.reload.metadata.to_h["pipeline_status"]
        assert_equal "succeeded", flow.generation_run.metadata.to_h["static_validation_status"]
        assert flow.generation_run.metadata.to_h["publication_files"].key?("index.html")
        assert_equal 2, flow.generation_run.metadata.to_h["artifact_fetched_file_count"]
        assert_equal 1, flow.generation_run.metadata.to_h.dig("artifact_file_counts", "html")
        assert_equal 1, flow.generation_run.metadata.to_h.dig("artifact_file_counts", "css")
        assert_equal 2, flow.generation_run.metadata.to_h["static_build_generated_file_count"]
        assert_includes flow.generation_run.metadata.to_h["static_build_log"], "Static build succeeded"
      end

      test "automatically assigns a missing page path and continues through publication" do
        @business.update!(metadata: @business.metadata.to_h.merge("lp_ga4_measurement_id" => "G-ABC123"))
        @business.business_services.create!(
          name: "AI受付 Service",
          status: "production",
          url: "https://service.example.com"
        )
        flow = LandingPageCreationFlow.new(
          business: @business,
          campaign: @campaign,
          attributes: { purpose: "google_ads" },
          strategy_builder_class: fake_strategy_builder
        ).call
        flow.landing_page.update!(
          metadata: flow.landing_page.metadata.to_h.merge(
            "ga4_page_path" => nil,
            "lp_repository_url" => "https://github.com/example/voice-analysis-pro"
          ).compact
        )
        flow.task.approve!
        Aicoo::Lovable::LandingPagePipeline.new.register_result!(
          business: @business,
          generation_run: flow.generation_run,
          project_url: "https://lovable.dev/projects/project-123",
          result_repository: "https://github.com/example/voice-analysis-pro",
          result_branch: "main"
        )
        publisher = FakePublisher.new
        importer = Aicoo::Lovable::ResultRepositoryImporter.new(
          source_client_class: fake_source_client_class,
          publisher:,
          configuration: Aicoo::CloudflarePages::Configuration.new(
            env: {
              "AICOO_GITHUB_TOKEN" => "token",
              "CLOUDFLARE_PAGES_PRODUCTION_URL" => "https://aicoo-lp.pages.dev"
            }
          )
        )

        result = importer.call(generation_run: flow.generation_run)

        assert_equal false, result.idempotent
        assert_equal 1, publisher.calls
        assert_equal "/voice-analysis-pro", flow.landing_page.reload.landing_page_ga4_path
        metadata = flow.generation_run.reload.metadata
        assert_equal "cloudflare_waiting", metadata["pipeline_status"]
        assert_equal "/voice-analysis-pro", metadata["page_path"]
        assert_equal "repository_name", metadata["page_path_generation_source"]
        assert_equal "page_pathを自動生成しました", metadata["page_path_generation_message"]
        assert metadata["page_path_generated_at"].present?
        overview = Aicoo::Lovable::PipelineOverview.new(
          generation_run: flow.generation_run,
          landing_page: flow.landing_page,
          task: flow.task,
          business: @business
        )
        assert overview.history.any? do |entry|
          entry.label == "page_pathを自動生成しました" && entry.detail == "/voice-analysis-pro"
        end
      end

      test "imports a registered repository without an approval task and stores preview commit details" do
        @business.update!(metadata: @business.metadata.to_h.merge("lp_ga4_measurement_id" => "G-ABC123"))
        @business.business_services.create!(
          name: "AI受付 Service",
          status: "production",
          url: "https://service.example.com"
        )
        prototype = LandingPageRegistry.new(business: @business).save!(
          campaign_id: @campaign.id,
          name: "既存GitHub LP",
          source_type: "github",
          repository_url: "https://github.com/example/existing-lp",
          branch: "main",
          ga4_page_path: "/existing-lp",
          public_status: "testing"
        )
        prepared = Aicoo::Lovable::LandingPagePipeline.new.prepare_repository_import!(
          business: @business,
          landing_page_prototype: prototype
        )
        publisher = FakePublisher.new
        importer = Aicoo::Lovable::ResultRepositoryImporter.new(
          source_client_class: fake_source_client_class,
          publisher:,
          configuration: Aicoo::CloudflarePages::Configuration.new(
            env: {
              "AICOO_GITHUB_TOKEN" => "token",
              "CLOUDFLARE_PAGES_PRODUCTION_URL" => "https://aicoo-lp.pages.dev"
            }
          )
        )

        result = importer.call(generation_run: prepared.generation_run)

        assert_equal false, result.idempotent
        metadata = prepared.generation_run.reload.metadata
        assert_equal "lovable-source-sha", metadata["source_commit_sha"]
        assert_equal "https://github.com/example/lovable-result/commit/lovable-source-sha", metadata["source_commit_url"]
        assert_equal "lovable-bot", metadata["source_commit_author"]
        assert_equal 2, metadata["source_changed_file_count"]
        assert_equal "https://aicoo-lp.pages.dev/ai-reception/", metadata["preview_url"]
        assert_equal "cloudflare_waiting", metadata["pipeline_status"]
        assert_nil metadata["auto_revision_task_id"]
      end

      private

      def fake_strategy_builder
        strategy = {
          "purpose_label" => "Google広告",
          "keywords" => [ "AI 電話受付" ],
          "search_intent" => "比較して申し込みたい",
          "target" => "電話対応に困る中小企業",
          "persona" => "少人数企業の経営者",
          "usp" => "24時間対応",
          "headline" => "電話対応をAIへ",
          "subheadline" => "取りこぼしを減らします",
          "cta" => "資料請求する",
          "faq" => [ "導入期間は？" ],
          "comparison_table" => [],
          "structure" => [ "ファーストビュー", "導入効果", "FAQ", "最終CTA" ],
          "seo_title" => "AI電話受付",
          "meta_description" => "AI電話受付の案内",
          "image_instructions" => [ "利用画面を表示" ],
          "color_direction" => "ブランドカラー",
          "design_direction" => "業務向け",
          "expected_profit_yen" => 48_000,
          "expected_cv" => 8.0,
          "expected_hourly_value_yen" => 19_200,
          "estimated_work_hours" => 2.5,
          "expected_value_source" => "business_actual",
          "confidence" => 0.7,
          "reason" => "広告流入と既存実績を基に生成"
        }
        Class.new do
          define_method(:initialize) { |**| }
          define_method(:call) { strategy }
        end
      end

      def fake_source_client_class
        Class.new do
          def initialize(**)
          end

          def snapshot!(commit_sha: nil)
            Aicoo::CloudflarePages::GithubRepositoryClient::RepositorySnapshot.new(
              commit_sha: commit_sha || "lovable-source-sha",
              commit_url: "https://github.com/example/lovable-result/commit/#{commit_sha || 'lovable-source-sha'}",
              committed_at: "2026-07-29T01:02:03Z",
              author: "lovable-bot",
              changed_paths: %w[index.html styles.css],
              files: {
                "index.html" => <<~HTML,
                  <!doctype html>
                  <html>
                    <head><title>AI受付</title><meta name="description" content="電話受付を自動化"></head>
                    <body><a class="cta" href="https://service.example.com">相談する</a></body>
                  </html>
                HTML
                "styles.css" => "body { margin: 0; }"
              }
            )
          end
        end
      end

      class FakePublisher
        attr_reader :calls

        def initialize
          @calls = 0
        end

        def publish!(landing_page:, generation_run:)
          @calls += 1
          publication = generation_run.metadata.to_h.fetch("publication", {}).merge(
            "status" => "github_pushed",
            "commit_sha" => "aicoo-lp-sha",
            "production_url" => "https://aicoo-lp.pages.dev/ai-reception/"
          )
          generation_run.update!(metadata: generation_run.metadata.to_h.merge("publication" => publication))
          Aicoo::CloudflarePages::LandingPagePublisher::Result.new(
            landing_page:,
            commit_sha: "aicoo-lp-sha",
            commit_url: "https://github.com/soregaaashiii/aicoo-lp/commit/aicoo-lp-sha",
            github_path: "public/ai-reception/",
            cloudflare_url: "https://aicoo-lp.pages.dev/ai-reception/",
            asset_source: "lovable_output",
            deleted: false
          )
        end
      end
    end
  end
end
