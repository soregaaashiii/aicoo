require "test_helper"

module Aicoo
  class CloudflarePagesDeploymentVerificationJobTest < ActiveJob::TestCase
    test "records a public url verification timeout on the related lovable run" do
      business = Business.create!(name: "Cloudflare Job Business", status: "building", business_type: "saas")
      campaign = business.business_campaigns.create!(name: "SEO", campaign_type: "seo", status: "active")
      run = AicooLabGenerationRun.create!(
        generation_type: "lp_generation",
        status: "succeeded",
        metadata: {
          "pipeline" => "lovable",
          "pipeline_status" => "cloudflare_waiting"
        }
      )
      landing_page = business.business_prototypes.create!(
        business_campaign: campaign,
        name: "Cloudflare LP",
        prototype_type: "url",
        location: "https://aicoo-lp.pages.dev/cloudflare-lp/",
        status: "active",
        metadata: {
          "role" => BusinessPrototype::EXTERNAL_LANDING_PAGE_ROLE,
          "lp_name" => "Cloudflare LP",
          "lp_public_status" => "testing",
          "cloudflare_url" => "https://aicoo-lp.pages.dev/cloudflare-lp/",
          "lovable_generation_run_id" => run.id
        }
      )
      verifier = Object.new
      verifier.define_singleton_method(:call) do |**|
        Aicoo::CloudflarePages::DeploymentVerifier::Result.new(
          completed: false,
          status: "pending",
          deployment_id: nil,
          url: nil,
          message: "Cloudflare Pagesの公開URL反映を待っています。"
        )
      end

      Aicoo::CloudflarePages::DeploymentVerifier.stub(:new, verifier) do
        CloudflarePagesDeploymentVerificationJob.perform_now(landing_page.id, "commit-sha", false, 10)
      end

      assert_equal "verification_timeout", landing_page.reload.metadata["cloudflare_deploy_status"]
      assert_equal "public_url_verification_timeout", run.reload.metadata["pipeline_status"]
      assert_equal "public_url_verification_timeout", run.metadata["lovable_error_code"]
    end

    test "keeps a temporary public url miss in automatic recovery" do
      business = Business.create!(name: "Cloudflare Retry Business", status: "building", business_type: "saas")
      campaign = business.business_campaigns.create!(name: "SEO", campaign_type: "seo", status: "active")
      run = AicooLabGenerationRun.create!(
        generation_type: "lp_generation",
        status: "succeeded",
        metadata: {
          "pipeline" => "lovable",
          "pipeline_status" => "cloudflare_waiting"
        }
      )
      landing_page = business.business_prototypes.create!(
        business_campaign: campaign,
        name: "Cloudflare Retry LP",
        prototype_type: "url",
        location: "https://aicoo-lp.pages.dev/cloudflare-retry-lp/",
        status: "active",
        metadata: {
          "role" => BusinessPrototype::EXTERNAL_LANDING_PAGE_ROLE,
          "lp_name" => "Cloudflare Retry LP",
          "lp_public_status" => "testing",
          "cloudflare_url" => "https://aicoo-lp.pages.dev/cloudflare-retry-lp/",
          "lovable_generation_run_id" => run.id
        }
      )
      verifier = Object.new
      verifier.define_singleton_method(:call) do |**|
        Aicoo::CloudflarePages::DeploymentVerifier::Result.new(
          completed: false,
          status: "pending",
          deployment_id: nil,
          url: nil,
          message: "Cloudflare Pagesの公開URL反映を待っています。"
        )
      end

      assert_enqueued_with(
        job: Aicoo::CloudflarePagesDeploymentVerificationJob,
        args: [ landing_page.id, "commit-sha", false, 2 ]
      ) do
        Aicoo::CloudflarePages::DeploymentVerifier.stub(:new, verifier) do
          CloudflarePagesDeploymentVerificationJob.perform_now(landing_page.id, "commit-sha", false, 1)
        end
      end

      metadata = landing_page.reload.metadata
      assert_equal 1, metadata["cloudflare_retry_count"]
      assert_equal "Cloudflare Pagesの公開URL反映を待っています。", metadata["cloudflare_last_message"]
      assert_nil run.reload.metadata["lovable_error_code"]
      assert_equal "cloudflare_waiting", run.metadata["pipeline_status"]
    end
  end
end
