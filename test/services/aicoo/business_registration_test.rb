require "test_helper"

class Aicoo::BusinessRegistrationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = @previous_queue_adapter
  end

  test "registers an idea with inferred settings and a today action" do
    result = nil

    assert_difference([ "Business.count", "ActionCandidate.count" ], 1) do
      assert_enqueued_with(job: Aicoo::BusinessRegistrationAnalysisJob) do
        result = described_service(
          mode: "idea",
          name: "AI電話受付",
          description: "営業代行会社向けの月額AI電話受付"
        ).call
      end
    end

    assert_nil result.prototype
    assert_equal "saas", result.business.business_type
    assert_equal "business_registration_v2", result.business.source
    assert_equal %w[顧客ヒアリング数 仮説検証数 初回コンバージョン], result.business.metadata["kpis"]
    assert_equal "business_registration", result.action_candidates.first.generation_source
    assert_equal "data_preparation", result.action_candidates.first.action_type
    assert_operator result.action_candidates.first.expected_profit_yen, :>, 0
    assert_equal false, result.action_candidates.first.metadata["codex_eligible"]
    assert result.business.business_data_source_settings.exists?(source_key: "explore")
  end

  test "registers a github prototype with minimal input" do
    result = described_service(
      mode: "prototype",
      name: "Call Desk",
      prototype_type: "github",
      prototype_location: "https://github.com/example/call-desk"
    ).call

    assert_equal "github", result.prototype.prototype_type
    assert_equal "queued", result.prototype.analysis_status
    assert_equal "mvp", result.business.lifecycle_stage
    assert result.business.business_data_source_settings.exists?(source_key: "github")
  end

  test "registers a published service from only its url" do
    result = described_service(
      mode: "published_service",
      prototype_location: "https://example.com"
    ).call

    assert_equal "example.com", result.business.name
    assert_equal "launched", result.business.status
    assert_equal "production", result.business.lifecycle_stage
    assert result.business.launched?
    assert_equal "url", result.prototype.prototype_type
    assert result.business.business_data_source_settings.exists?(source_key: "ga4")
    assert result.business.business_data_source_settings.exists?(source_key: "gsc")
  end

  private

  def described_service(**attributes)
    Aicoo::BusinessRegistration.new(**attributes)
  end
end
