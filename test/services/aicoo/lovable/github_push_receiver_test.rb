require "test_helper"

module Aicoo
  module Lovable
    class GithubPushReceiverTest < ActiveSupport::TestCase
      class RecordingConfiguration
        attr_reader :records

        def initialize
          @records = []
        end

        def record!(**attributes)
          records << attributes
        end
      end

      class TransientlyFailingJob
        class << self
          attr_accessor :calls, :wait

          def reset!
            self.calls = 0
            self.wait = nil
          end

          def perform_later(*)
            self.calls += 1
            raise "queue unavailable" if calls == 1
          end

          def set(wait:)
            self.wait = wait
            self
          end
        end
      end

      setup do
        @business = Business.create!(name: "Webhook Recovery Business", status: "building", business_type: "saas")
        campaign = @business.business_campaigns.create!(name: "SEO", campaign_type: "seo", status: "active")
        @landing_page = @business.business_prototypes.create!(
          business_campaign: campaign,
          name: "Webhook Recovery LP",
          prototype_type: "github",
          location: "https://github.com/example/recovery-result",
          status: "active",
          metadata: {
            "role" => BusinessPrototype::EXTERNAL_LANDING_PAGE_ROLE,
            "lp_name" => "Webhook Recovery LP",
            "lp_public_status" => "testing"
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
            "lovable_result_repository" => "https://github.com/example/recovery-result",
            "lovable_result_branch" => "main"
          }
        )
        @landing_page.update!(metadata: @landing_page.metadata.to_h.merge("lovable_generation_run_id" => @run.id))
        TransientlyFailingJob.reset!
      end

      test "automatically schedules one delayed retry when webhook job enqueue temporarily fails" do
        result = GithubPushReceiver.new(
          configuration: RecordingConfiguration.new,
          job_class: TransientlyFailingJob
        ).call(
          event: "push",
          delivery_id: "delivery-recovery",
          payload_size: 512,
          payload: {
            ref: "refs/heads/main",
            after: "source-commit",
            deleted: false,
            repository: { full_name: "example/recovery-result" }
          }
        )

        assert_equal "accepted", result.status
        assert_equal 2, TransientlyFailingJob.calls
        assert_equal 30.seconds, TransientlyFailingJob.wait
        metadata = @run.reload.metadata
        assert_equal "retrying", metadata["pipeline_recovery_status"]
        assert_equal "webhook_enqueue_failed", metadata["lovable_error_code"]
        assert_equal 1, metadata["pipeline_retry_count"]
      end
    end
  end
end
