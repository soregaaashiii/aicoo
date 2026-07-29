require "test_helper"
require "openssl"

module Webhooks
  class GithubControllerTest < ActionDispatch::IntegrationTest
    setup do
      @business = Business.create!(name: "Webhook LP Business", status: "building", business_type: "saas")
      @campaign = @business.business_campaigns.create!(name: "SEO", campaign_type: "seo", status: "active")
      @landing_page = @business.business_prototypes.create!(
        business_campaign: @campaign,
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
      @run = AicooLabGenerationRun.create!(
        generation_type: "lp_generation",
        status: "succeeded",
        metadata: {
          "pipeline" => "lovable",
          "pipeline_status" => "github_webhook_waiting",
          "business_id" => @business.id,
          "landing_page_prototype_id" => @landing_page.id,
          "lovable_result_repository" => "https://github.com/example/lovable-result",
          "lovable_result_branch" => "main",
          "publication" => {}
        }
      )
      @landing_page.update!(metadata: @landing_page.metadata.to_h.merge("lovable_generation_run_id" => @run.id))
      @secret = "webhook-secret"
      profile = DataSourceCostProfile.find_or_initialize_by(source_key: Aicoo::Lovable::GithubWebhookConfiguration::PROFILE_KEY)
      profile.update!(
        name: "Lovable GitHub Webhook",
        execution_mode: "auto",
        enabled: true,
        metadata: profile.metadata.to_h.merge("credentials" => { "secret" => @secret })
      )
      @payload = {
        ref: "refs/heads/main",
        after: "abc123def456",
        deleted: false,
        repository: {
          full_name: "example/lovable-result",
          html_url: "https://github.com/example/lovable-result"
        }
      }
    end

    test "accepts a signed push and enqueues the exact commit once" do
      assert_enqueued_with(
        job: Aicoo::LovableResultImportJob,
        args: [ @run.id, "abc123def456", "example/lovable-result:main:abc123def456" ]
      ) do
        post_signed_push(@payload)
      end

      assert_response :accepted
      assert_equal "github_webhook_received", @run.reload.metadata["pipeline_status"]
      assert_equal "abc123def456", @run.metadata["github_webhook_commit_sha"]
      assert_equal "github_webhook_received", @landing_page.reload.metadata["planning_status"]
    end

    test "uses the saved landing page repository when the generation run predates setup" do
      @run.update!(metadata: @run.metadata.to_h.except("lovable_result_repository", "lovable_result_branch"))

      assert_enqueued_with(
        job: Aicoo::LovableResultImportJob,
        args: [ @run.id, "abc123def456", "example/lovable-result:main:abc123def456" ]
      ) do
        post_signed_push(@payload)
      end

      assert_response :accepted
      assert_equal "https://github.com/example/lovable-result", @run.reload.metadata["lovable_result_repository"]
      assert_equal "main", @run.metadata["lovable_result_branch"]
    end

    test "does not enqueue or publish a duplicate delivery for the same repository branch and commit" do
      assert_enqueued_jobs 1 do
        post_signed_push(@payload)
        assert_response :accepted
        post_signed_push(@payload, delivery_id: "delivery-2")
        assert_response :success
      end

      assert_equal true, response.parsed_body["duplicate"]
      assert_equal 1, @run.reload.metadata.fetch("github_webhook_receipts").size
    end

    test "rejects a signature mismatch before matching a landing page" do
      assert_no_enqueued_jobs do
        post github_webhook_url,
             params: @payload.to_json,
             headers: github_headers(signature: "sha256=invalid")
      end

      assert_response :unauthorized
      assert_equal "signature_mismatch", response.parsed_body["error"]
      assert_equal "github_webhook_waiting", @run.reload.metadata["pipeline_status"]
    end

    test "records a repository mismatch without starting import" do
      payload = @payload.deep_merge(repository: {
        full_name: "example/other-result",
        html_url: "https://github.com/example/other-result"
      })

      assert_no_enqueued_jobs { post_signed_push(payload) }

      assert_response :success
      assert_equal "repository_mismatch", response.parsed_body["reason"]
      assert_equal "github_webhook_waiting", @run.reload.metadata["pipeline_status"]
    end

    test "accepts a signed github ping as connection verification" do
      body = { zen: "Keep it logically awesome." }.to_json
      post github_webhook_url,
           params: body,
           headers: github_headers(event: "ping", signature: signature_for(body))

      assert_response :success
      assert_equal "ping", response.parsed_body["status"]
    end

    private

    def post_signed_push(payload, delivery_id: "delivery-1")
      body = payload.to_json
      post github_webhook_url,
           params: body,
           headers: github_headers(delivery_id:, signature: signature_for(body))
    end

    def github_headers(event: "push", delivery_id: "delivery-1", signature:)
      {
        "CONTENT_TYPE" => "application/json",
        "X-GitHub-Event" => event,
        "X-GitHub-Delivery" => delivery_id,
        "X-Hub-Signature-256" => signature
      }
    end

    def signature_for(body)
      "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', @secret, body)}"
    end
  end
end
