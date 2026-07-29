require "test_helper"

class LovableLandingPagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:suelog)
  end

  test "shows the canonical LP detail with the embedded pipeline explorer" do
    get business_lovable_landing_page_url(@business)

    assert_response :success
    assert_includes response.body, "LP詳細"
    assert_not_includes response.body, "LP Studio"
    assert_includes response.body, "lovable-pipeline-live"
    assert_includes response.body, "1 / 13"
    assert_includes response.body, "LP作成"
    assert_includes response.body, "承認"
    assert_includes response.body, "Lovable"
    assert_includes response.body, "GitHub Push"
    assert_includes response.body, "Webhook"
    assert_includes response.body, "成果物取得"
    assert_includes response.body, "静的build"
    assert_includes response.body, "aicoo-lp Push"
    assert_includes response.body, "Cloudflare"
    assert_includes response.body, "HTTP200確認"
    assert_includes response.body, "GA4"
    assert_includes response.body, "GSC"
    assert_includes response.body, "Learning"
    assert_includes response.body, "Pipeline Explorer"
    assert_select "[data-pipeline-diagnosis]", 1
    assert_includes response.body, "診断結果"
    assert_includes response.body, "接続状態"
    assert_includes response.body, "原因"
    assert_includes response.body, "必要設定"
    assert_includes response.body, "設定場所"
    assert_includes response.body, "直し方"
    assert_select "details[data-pipeline-explorer-stage]", 13
    assert_select "details[data-pipeline-explorer-stage='github_source_push'] summary", text: /GitHub Push/
    assert_select "details[data-pipeline-explorer-stage='webhook']", text: /Webhook URL/
    assert_select "details[data-pipeline-explorer-stage='cloudflare']", text: /Cloudflare Project/
    assert_select "details[data-pipeline-explorer-stage='ga4']", text: /Business共通設定/
    assert_select "details[data-pipeline-explorer-stage='learning']", text: /Snapshot/
    assert_includes response.body, "次にやること"
    assert_includes response.body, "＋LP作成"
    assert_select "form[action='#{start_creation_business_lovable_landing_page_path(@business)}']", 1
    assert_select ".aicoo-breadcrumb", text: /CEO.*#{Regexp.escape(@business.name)}.*LP/
    assert_not_includes response.body, "BusinessのLP一覧へ"
    assert_not_includes response.body, "Businessへ戻る"
    assert_includes response.body, "5000"
    assert_not_includes response.body, ">Lovableで作成<"
    assert_not_includes response.body, ">Promptを見る<"
    assert_not_includes response.body, ">Lovableで編集<"
    assert_not_includes response.body, "lovable-phase-strip"
    assert_includes response.body, "openStages"
    assert_includes response.body, "data-pipeline-explorer-stage"
  end

  test "pipeline diagnosis explains github permissions and offers one next action" do
    campaign = @business.business_campaigns.create!(name: "Diagnosis Campaign", campaign_type: "seo", status: "active")
    landing_page = @business.business_prototypes.create!(
      business_campaign: campaign,
      name: "Diagnosis LP",
      prototype_type: "github",
      location: "https://github.com/example/private-lp",
      status: "active",
      metadata: {
        "role" => BusinessPrototype::EXTERNAL_LANDING_PAGE_ROLE,
        "lp_name" => "Diagnosis LP",
        "lp_public_status" => "testing"
      }
    )
    run = AicooLabGenerationRun.create!(
      generation_type: "lp_generation",
      status: "failed",
      prompt: "Import LP",
      error_message: "GitHub Repository example/private-lp へアクセスできません。",
      metadata: {
        "pipeline" => "lovable",
        "pipeline_status" => "github_webhook_waiting",
        "business_id" => @business.id,
        "landing_page_prototype_id" => landing_page.id,
        "version" => 1,
        "repository_import" => true,
        "lovable_result_repository" => "https://github.com/example/private-lp",
        "lovable_result_branch" => "main",
        "lovable_error_code" => "github_permission_error",
        "lovable_error_message" => "GitHub Repository example/private-lp へアクセスできません。"
      }
    )
    landing_page.update!(metadata: landing_page.metadata.to_h.merge("lovable_generation_run_id" => run.id))

    get business_lovable_landing_page_url(@business, landing_page_id: landing_page.id)

    assert_response :success
    assert_select "[data-pipeline-diagnosis]", text: /GitHub.*要設定/
    assert_select "[data-pipeline-explorer-stage='github_source_push']", text: /Fine-grained Token/
    assert_select "[data-pipeline-explorer-stage='github_source_push']", text: /Contents Read/
    assert_select ".lovable-pipeline-guidance form[action^='#{recheck_pipeline_business_lovable_landing_page_path(@business)}']", 1
    assert_select ".lovable-pipeline-guidance .compact-actions .button", 1
  end

  test "starts and approves an unstarted landing page without leaving its detail" do
    campaign = @business.business_campaigns.create!(name: "Detail SEO", campaign_type: "seo", status: "active")
    landing_page = @business.business_prototypes.create!(
      business_campaign: campaign,
      name: "Detail LP",
      prototype_type: "other",
      location: "手動指定（未設定）",
      status: "active",
      metadata: {
        "role" => BusinessPrototype::EXTERNAL_LANDING_PAGE_ROLE,
        "lp_name" => "Detail LP",
        "lp_public_status" => "testing"
      }
    )

    assert_no_difference("BusinessPrototype.count") do
      assert_difference([ "AicooLabGenerationRun.count", "ActionCandidate.count", "AutoRevisionTask.count" ], 1) do
        post start_creation_business_lovable_landing_page_url(@business), params: {
          landing_page_id: landing_page.id,
          lp_plan: { purpose: "seo" }
        }
      end
    end

    assert_redirected_to business_lovable_landing_page_url(
      @business,
      landing_page_id: landing_page.id,
      anchor: "lovable-pipeline-live"
    )
    landing_page.reload
    task = @business.auto_revision_tasks.find(landing_page.metadata.fetch("auto_revision_task_id"))
    run = AicooLabGenerationRun.find(landing_page.metadata.fetch("lovable_generation_run_id"))
    assert_equal "waiting_approval", landing_page.metadata["planning_status"]
    assert_equal "waiting_approval", task.status
    assert_equal "prompt_ready", run.metadata["pipeline_status"]

    get business_lovable_landing_page_url(@business, landing_page_id: landing_page.id)
    assert_response :success
    assert_select "li[data-pipeline-stage='landing_page'].status-completed", 1
    assert_select "#lovable-pipeline-live form[action^='#{approve_business_lovable_landing_page_path(@business)}']", 1
    assert_not_includes response.body, "BusinessのLP一覧へ"

    patch approve_business_lovable_landing_page_url(@business), params: {
      landing_page_id: landing_page.id,
      auto_revision_task_id: task.id
    }
    assert_redirected_to business_lovable_landing_page_url(
      @business,
      landing_page_id: landing_page.id,
      anchor: "lovable-pipeline-live"
    )
    assert_equal "approved", task.reload.status
    assert_equal "lovable_handoff_ready", run.reload.metadata["pipeline_status"]

    get business_lovable_landing_page_url(@business, landing_page_id: landing_page.id)
    assert_select "#lovable-pipeline-live a", text: "Lovableを開いてGenerate", count: 1
    assert_select "#lovable-pipeline-live form[action^='#{approve_business_lovable_landing_page_path(@business)}']", 0
  end

  test "creates an official Build URL version regardless of MCP configuration" do
    assert_difference("AicooLabGenerationRun.count", 1) do
      post business_lovable_landing_page_url(@business)
    end

    run = AicooLabGenerationRun.last
    assert_redirected_to run.metadata["build_url"]
    assert_equal "lovable_handoff_ready", run.metadata["pipeline_status"]
    assert_equal "build_with_url", run.metadata["launcher"]
  end

  test "prepares an editable prompt without generating a Build URL" do
    assert_difference("AicooLabGenerationRun.count", 1) do
      post prepare_business_lovable_landing_page_url(@business)
    end

    run = AicooLabGenerationRun.last
    assert_redirected_to business_lovable_landing_page_path(@business, anchor: "lovable-prompt")
    assert_equal "draft", run.status
    assert_equal "prompt_ready", run.metadata["pipeline_status"]
    assert_nil run.metadata["build_url"]

    patch update_prompt_version_business_lovable_landing_page_url(@business, generation_run_id: run.id), params: { prompt: "Edited prompt" }
    assert_redirected_to business_lovable_landing_page_path(@business, anchor: "lovable-prompt")
    assert_equal "Edited prompt", run.reload.prompt
  end

  test "business detail routes LP creation through the purpose based form" do
    get business_url(@business)

    assert_response :success
    assert_includes response.body, "＋LP追加"
    assert_includes response.body, "処理中LP"
    assert_includes response.body, "失敗LP"
    assert_includes response.body, business_lovable_landing_page_path(@business)
    assert_not_includes response.body, ">Lovableで作成<"
    assert_not_includes response.body, ">Promptを見る<"
    assert_not_includes response.body, ">公開LP管理<"
    assert_not_includes response.body, ">LP編集<"
  end

  test "result repository waits for github webhook without a manual fetch button" do
    campaign = @business.business_campaigns.create!(name: "Webhook Campaign", campaign_type: "seo", status: "active")
    landing_page = @business.business_prototypes.create!(
      business_campaign: campaign,
      name: "Webhook LP",
      prototype_type: "github",
      location: "https://github.com/example/lovable-result",
      status: "active",
      metadata: {
        "role" => BusinessPrototype::EXTERNAL_LANDING_PAGE_ROLE,
        "lp_name" => "Webhook LP",
        "lp_public_status" => "testing",
        "ga4_page_path" => "/webhook-lp"
      }
    )
    run = AicooLabGenerationRun.create!(
      generation_type: "lp_generation",
      status: "succeeded",
      prompt: "Create LP",
      metadata: {
        "pipeline" => "lovable",
        "pipeline_status" => "github_webhook_waiting",
        "business_id" => @business.id,
        "landing_page_id" => 1,
        "landing_page_prototype_id" => landing_page.id,
        "version" => 1,
        "version_label" => "v1",
        "build_url" => "https://lovable.dev/?autosubmit=true#prompt=test",
        "lovable_result_repository" => "https://github.com/example/lovable-result",
        "lovable_result_branch" => "main",
        "publication" => {}
      }
    )
    landing_page.update!(metadata: landing_page.metadata.to_h.merge("lovable_generation_run_id" => run.id))

    get business_lovable_landing_page_url(@business, landing_page_id: landing_page.id)

    assert_response :success
    assert_includes response.body, "4 / 13"
    assert_includes response.body, "LovableでGenerateしてください"
    assert_includes response.body, "data-refresh-enabled=\"true\""
    assert_not_includes response.body, "保存してGitHub Pushを待つ"
    assert_not_includes response.body, "Previewを取り込む"
    assert_not_includes response.body, ">公開<"
    assert_not_includes response.body, ">生成結果を取得<"
  end

  test "approval remains on the same LP detail until lovable is ready" do
    campaign = @business.business_campaigns.create!(name: "Approval Campaign", campaign_type: "seo", status: "active")
    landing_page = @business.business_prototypes.create!(
      business_campaign: campaign,
      name: "Approval LP",
      prototype_type: "github",
      location: "https://github.com/example/approval-lp",
      status: "active",
      metadata: {
        "role" => BusinessPrototype::EXTERNAL_LANDING_PAGE_ROLE,
        "lp_name" => "Approval LP",
        "lp_public_status" => "testing",
        "planning_status" => "waiting_approval"
      }
    )
    run = AicooLabGenerationRun.create!(
      generation_type: "lp_generation",
      status: "draft",
      prompt: "Create approval LP",
      metadata: {
        "pipeline" => "lovable",
        "pipeline_status" => "prompt_ready",
        "business_id" => @business.id,
        "landing_page_prototype_id" => landing_page.id,
        "version" => 1,
        "publication" => {}
      }
    )
    task = AutoRevisionTask.create!(
      action_candidate: action_candidates(:nagazakicho_article),
      business: @business,
      title: "Approval LP",
      execution_prompt: run.prompt,
      status: "waiting_approval",
      metadata: {
        "workflow_type" => "external_lp_creation",
        "landing_page_prototype_id" => landing_page.id,
        "lovable_generation_run_id" => run.id,
        "pipeline_stage" => "lovable_pending"
      }
    )
    run.update!(metadata: run.metadata.to_h.merge("auto_revision_task_id" => task.id))
    landing_page.update!(metadata: landing_page.metadata.to_h.merge("lovable_generation_run_id" => run.id))

    get business_lovable_landing_page_url(@business, landing_page_id: landing_page.id)

    assert_response :success
    assert_includes response.body, "2 / 13"
    assert_includes response.body, "承認待ち"
    assert_select "#lovable-pipeline-live form[action^='#{approve_business_lovable_landing_page_path(@business)}']", 1
    assert_select "#lovable-pipeline-live form[target='_blank']", 0
    assert_select "#lovable-pipeline-live[data-refresh-url*='landing_page_id=#{landing_page.id}']", 1
  end

  test "pipeline status endpoint renders the same live partial without the full page" do
    campaign = @business.business_campaigns.create!(name: "Live Campaign", campaign_type: "seo", status: "active")
    landing_page = @business.business_prototypes.create!(
      business_campaign: campaign,
      name: "Live LP",
      prototype_type: "github",
      location: "https://github.com/example/live-lp",
      status: "active",
      metadata: {
        "role" => BusinessPrototype::EXTERNAL_LANDING_PAGE_ROLE,
        "lp_name" => "Live LP",
        "lp_public_status" => "testing",
        "planning_status" => "github_webhook_received"
      }
    )
    run = AicooLabGenerationRun.create!(
      generation_type: "lp_generation",
      status: "succeeded",
      prompt: "Create LP",
      metadata: {
        "pipeline" => "lovable",
        "pipeline_status" => "artifact_fetching",
        "business_id" => @business.id,
        "landing_page_prototype_id" => landing_page.id,
        "version" => 1,
        "github_webhook_received_at" => Time.current.iso8601
      }
    )
    landing_page.update!(metadata: landing_page.metadata.to_h.merge("lovable_generation_run_id" => run.id))

    get pipeline_status_business_lovable_landing_page_url(@business, landing_page_id: landing_page.id)

    assert_response :success
    assert_includes response.body, "lovable-pipeline-live"
    assert_includes response.body, "6 / 13"
    assert_includes response.body, "成果物取得"
    assert_includes response.body, "現在AIが処理中です。操作は不要です。"
    assert_select "details[data-pipeline-explorer-stage]", 13
    assert_select "details[data-pipeline-explorer-stage='artifact_fetch'][open]", 1
    assert_select "details[data-pipeline-explorer-stage='artifact_fetch']", text: /取得ファイル数/
    assert_select "[data-pipeline-diagnosis]", 1
    assert_not_includes response.body, "<html"
    assert_not_includes response.body, "LP Studio"
  end

  test "LP detail and live refresh only read the saved diagnosis snapshot" do
    campaign = @business.business_campaigns.create!(name: "Saved Diagnosis", campaign_type: "seo", status: "active")
    landing_page = @business.business_prototypes.create!(
      business_campaign: campaign,
      name: "Saved Diagnosis LP",
      prototype_type: "github",
      location: "https://github.com/example/saved-diagnosis",
      status: "active",
      metadata: {
        "role" => BusinessPrototype::EXTERNAL_LANDING_PAGE_ROLE,
        "lp_name" => "Saved Diagnosis LP",
        "lp_public_status" => "testing"
      }
    )
    run = AicooLabGenerationRun.create!(
      generation_type: "lp_generation",
      status: "running",
      metadata: {
        "pipeline" => "lovable",
        "pipeline_status" => "github_webhook_waiting",
        "business_id" => @business.id,
        "landing_page_prototype_id" => landing_page.id,
        "version" => 1
      }
    )
    landing_page.update!(metadata: landing_page.metadata.to_h.merge("lovable_generation_run_id" => run.id))
    run.reload
    assert run.metadata[Aicoo::Lovable::PipelineDiagnosisSnapshot::METADATA_KEY].present?

    forbidden = ->(*) { raise "normal GET must not run live diagnosis" }
    forbidden_keywords = ->(**) { raise "normal GET must not call an external checker" }
    Aicoo::Lovable::PipelineDiagnosis.stub(:new, forbidden) do
      Aicoo::BusinessConnectionStatus.stub(:new, forbidden) do
        Aicoo::Lovable::LearningSummary.stub(:new, forbidden) do
          Aicoo::CloudflarePages::GithubRepositoryClient.stub(:new, forbidden_keywords) do
            Aicoo::CloudflarePages::DeploymentVerifier.stub(:new, forbidden_keywords) do
              get business_lovable_landing_page_url(@business, landing_page_id: landing_page.id)
              assert_response :success
              assert_select "[data-pipeline-diagnosis]", 1

              get pipeline_status_business_lovable_landing_page_url(@business, landing_page_id: landing_page.id)
              assert_response :success
              assert_select "[data-pipeline-diagnosis]", 1
            end
          end
        end
      end
    end
  end

  test "manual recheck runs the live checker and replaces the saved snapshot" do
    campaign = @business.business_campaigns.create!(name: "Manual Recheck", campaign_type: "seo", status: "active")
    landing_page = @business.business_prototypes.create!(
      business_campaign: campaign,
      name: "Manual Recheck LP",
      prototype_type: "github",
      location: "https://github.com/example/manual-recheck",
      status: "active",
      metadata: {
        "role" => BusinessPrototype::EXTERNAL_LANDING_PAGE_ROLE,
        "lp_name" => "Manual Recheck LP",
        "lp_public_status" => "testing"
      }
    )
    run = AicooLabGenerationRun.create!(
      generation_type: "lp_generation",
      status: "running",
      metadata: {
        "pipeline" => "lovable",
        "pipeline_status" => "github_webhook_waiting",
        "business_id" => @business.id,
        "landing_page_prototype_id" => landing_page.id,
        "lovable_result_repository" => "https://github.com/example/manual-recheck",
        "lovable_result_branch" => "main",
        "version" => 1
      }
    )
    landing_page.update!(metadata: landing_page.metadata.to_h.merge("lovable_generation_run_id" => run.id))
    checked = Aicoo::Lovable::PipelineRechecker::Result.new(
      component: "github",
      ok: false,
      level: "settings",
      code: "github_token_missing",
      cause: "Tokenを設定してください。",
      required_setting: "Contents Read",
      settings_location: "GitHub Settings",
      fix_steps: [ "Tokenを更新する" ],
      details: {
        "repository" => "example/manual-recheck",
        "branch" => "main"
      }
    )
    checker = Object.new
    checker.define_singleton_method(:call) { |**| checked }

    Aicoo::Lovable::PipelineRechecker.stub(:new, checker) do
      post recheck_pipeline_business_lovable_landing_page_url(
        @business,
        landing_page_id: landing_page.id
      ), params: { component: "github" }
    end

    assert_redirected_to business_lovable_landing_page_url(
      @business,
      landing_page_id: landing_page.id,
      anchor: "lovable-pipeline-live"
    )
    snapshot = run.reload.metadata.fetch(Aicoo::Lovable::PipelineDiagnosisSnapshot::METADATA_KEY)
    assert_equal "manual_recheck", snapshot["source"]
    assert_equal "Tokenを設定してください。", snapshot["components"].find { |row| row["key"] == "github" }["cause"]
  end
end
