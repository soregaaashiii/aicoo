require "test_helper"

module Aicoo
  class OwnerExecutionQueueBuilderTest < ActiveSupport::TestCase
    setup do
      OwnerExecutionQueueItem.delete_all
      AicooSetting.current.update!(
        daily_owner_queue_limit: 10,
        auto_queue_low_risk_enabled: true,
        auto_queue_medium_risk_enabled: true,
        auto_queue_high_risk_enabled: false
      )
    end

    test "creates queue items from pending opportunity result and calibration" do
      create_pending_opportunity
      create_approved_candidate(title: "Approved queue candidate")
      create_codex_prompt_draft
      create_completed_execution_without_result
      create_pending_calibration

      result = OwnerExecutionQueueBuilder.new(due_on: Date.current, generated_from: "test").call

      assert_operator result.created.size, :>=, 3
      assert OwnerExecutionQueueItem.exists?(item_type: "opportunity")
      assert OwnerExecutionQueueItem.exists?(item_type: "result_registration")
      assert OwnerExecutionQueueItem.exists?(item_type: "calibration")
      assert_not OwnerExecutionQueueItem.exists?(item_type: "action_candidate")
      assert_not OwnerExecutionQueueItem.exists?(item_type: "codex_prompt_draft")
    end

    test "does not create duplicates for same day" do
      create_pending_opportunity

      assert_difference("OwnerExecutionQueueItem.count", 1) do
        OwnerExecutionQueueBuilder.new.call
      end

      assert_no_difference("OwnerExecutionQueueItem.count") do
        OwnerExecutionQueueBuilder.new.call
      end
    end

    test "respects daily limit" do
      AicooSetting.current.update!(daily_owner_queue_limit: 2)
      4.times { |index| create_pending_opportunity(title: "Opportunity #{index}", expected_value_yen: 50_000 + index) }

      result = OwnerExecutionQueueBuilder.new.call

      assert_equal 2, result.created.size
    end

    test "does not queue approved action candidates because approval flow is handled by auto revision tasks" do
      create_approved_candidate(
        title: "認証 migration high risk",
        execution_prompt: "認証とmigrationを変更する"
      )

      result = OwnerExecutionQueueBuilder.new.call

      assert_empty result.created
      assert_empty result.high_risk
      assert_not OwnerExecutionQueueItem.exists?(risk_level: "high")
      assert_not OwnerExecutionQueueItem.exists?(item_type: "action_candidate")
    end

    test "priority score uses expected value and confidence for opportunity" do
      weak = create_pending_opportunity(title: "Medium opportunity", expected_value_yen: 10_000, confidence: 60)
      strong = create_pending_opportunity(title: "Strong opportunity", expected_value_yen: 200_000, confidence: 95)

      OwnerExecutionQueueBuilder.new.call

      weak_item = OwnerExecutionQueueItem.find_by!(item_type: "opportunity", item_id: weak.id)
      strong_item = OwnerExecutionQueueItem.find_by!(item_type: "opportunity", item_id: strong.id)
      assert_operator strong_item.priority_score, :>, weak_item.priority_score
    end

    private

    def create_pending_opportunity(title: "Pending opportunity", expected_value_yen: 100_000, confidence: 90)
      OpportunityDiscoveryItem.create!(
        business: businesses(:suelog),
        title:,
        status: "pending",
        expected_value_yen:,
        confidence:,
        opportunity_score: confidence
      )
    end

    def create_approved_candidate(title:, execution_prompt: "SEOタイトルを改善")
      ActionCandidate.create!(
        business: businesses(:suelog),
        title:,
        status: "approved",
        action_type: "seo_improvement",
        execution_prompt:,
        immediate_value_yen: 30_000,
        final_score: 12_000,
        success_probability: 1,
        expected_hours: 1
      )
    end

    def create_codex_prompt_draft
      CodexPromptDraft.create!(
        action_candidate: action_candidates(:nagazakicho_article),
        business: businesses(:suelog),
        title: "Draft queue item",
        prompt_body: "body",
        risk_level: "low",
        status: "draft",
        verification_commands: CodexPromptDraft::DEFAULT_VERIFICATION_COMMANDS,
        metadata: { "expected_value_yen" => 20_000 }
      )
    end

    def create_completed_execution_without_result
      candidate = create_approved_candidate(title: "Completed execution candidate")
      candidate.create_action_execution!(status: "completed", execution_type: "manual", completed_at: Time.current)
    end

    def create_pending_calibration
      ActionPredictionCalibration.create!(
        action_type: "seo_improvement",
        sample_count: 10,
        approval_status: "pending",
        warning_level: "warning",
        profit_calibration_factor: 1,
        probability_calibration_factor: 1
      )
    end
  end
end
