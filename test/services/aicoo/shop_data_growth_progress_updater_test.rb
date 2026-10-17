require "test_helper"

module Aicoo
  class ShopDataGrowthProgressUpdaterTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      @candidate = action_candidates(:nagazakicho_article)
      @candidate.update_columns(
        title: "吸えログの優先エリアに店舗データを3件追加する",
        action_type: "data_preparation",
        status: "idea",
        metadata: {
          "metric_rule" => ShopDataGrowthPlan::METRIC_RULE,
          "execution_mode" => "data_operation",
          "initial_count" => 0,
          "target_amount" => 3,
          "benchmark_value" => 3,
          "evidence" => {
            "current_value" => 0,
            "benchmark_value" => 3,
            "target_amount" => 3
          }
        },
        created_at: 1.hour.ago,
        updated_at: 1.hour.ago
      )
      @candidate.reload
    end

    test "updates saved progress from unique shop creation activities" do
      insert_shop_activity(resource_id: "shop-1")
      insert_shop_activity(resource_id: "shop-1", idempotency_key: "shop-1-created-again")
      insert_shop_activity(resource_id: "shop-2")

      result = ShopDataGrowthProgressUpdater.sync_business!(@business)

      progress = @candidate.reload.metadata.fetch("shop_data_growth_progress")
      assert_equal 1, result.updated_count
      assert_equal 2, progress.fetch("completed_count")
      assert_equal 1, progress.fetch("remaining_count")
      assert_equal "idea", @candidate.status
      assert_nil @candidate.action_result
    end

    test "ignores shop activities that happened before the candidate started" do
      insert_shop_activity(resource_id: "old-shop", occurred_at: @candidate.created_at - 1.minute)
      insert_shop_activity(resource_id: "new-shop")

      ShopDataGrowthProgressUpdater.sync_business!(@business)

      progress = @candidate.reload.metadata.fetch("shop_data_growth_progress")
      assert_equal 1, progress.fetch("completed_count")
      assert_equal 2, progress.fetch("remaining_count")
    end

    test "ignores updates and activities from other source apps" do
      insert_shop_activity(resource_id: "updated-shop", activity_type: "shop_profile_updated")
      insert_shop_activity(resource_id: "other-source", source_app: "other")

      ShopDataGrowthProgressUpdater.sync_business!(@business)

      progress = @candidate.reload.metadata.fetch("shop_data_growth_progress")
      assert_equal 0, progress.fetch("completed_count")
      assert_equal 3, progress.fetch("remaining_count")
    end

    test "completes candidate through the existing execution and result path at target" do
      3.times { |index| insert_shop_activity(resource_id: "shop-#{index + 1}") }

      result = ShopDataGrowthProgressUpdater.sync_business!(@business)

      @candidate.reload
      assert_equal 1, result.completed_count
      assert_equal "done", @candidate.status
      assert_equal "completed", @candidate.action_execution.status
      assert_equal 3, @candidate.action_result.metadata.dig("action_candidate_completion", "registered_count")
      assert_equal "shop_data_growth_progress", @candidate.metadata.fetch("execution_record_source")
      assert @candidate.metadata.dig("shop_data_growth_progress", "completed_at").present?
    end

    test "shop created callback synchronizes and completes without manual operation" do
      @candidate.update_columns(
        metadata: @candidate.metadata.merge(
          "target_amount" => 1,
          "benchmark_value" => 1,
          "evidence" => { "current_value" => 0, "benchmark_value" => 1, "target_amount" => 1 }
        ),
        updated_at: Time.current
      )

      with_activity_trigger_stub do
        BusinessActivityLog.record!(
          business: @business,
          attributes: activity_attributes(resource_id: "callback-shop")
        )
      end

      assert_equal "done", @candidate.reload.status
      assert_equal 1, @candidate.action_result.metadata.dig("action_candidate_completion", "registered_count")
    end

    private

    def insert_shop_activity(
      resource_id:,
      occurred_at: Time.current,
      idempotency_key: nil,
      activity_type: "shop_created",
      source_app: "suelog"
    )
      now = Time.current
      BusinessActivityLog.insert_all!([ {
        business_id: @business.id,
        source_app:,
        activity_type:,
        resource_type: "Shop",
        resource_id:,
        title: "店舗を追加",
        occurred_at:,
        detected_at: now,
        changed_fields: {},
        before_snapshot: {},
        after_snapshot: {},
        metadata: {},
        source_method: "logger",
        evaluation_status: "pending",
        idempotency_key: idempotency_key || "#{resource_id}-#{occurred_at.to_f}",
        created_at: now,
        updated_at: now
      } ])
    end

    def activity_attributes(resource_id:)
      {
        source_app: "suelog",
        activity_type: "shop_created",
        resource_type: "Shop",
        resource_id:,
        title: "店舗を追加",
        occurred_at: Time.current,
        idempotency_key: "#{resource_id}-created"
      }
    end

    def successful_trigger_result
      ActivityEvaluationTrigger::Result.new(
        builder_should_run_count: 1,
        builder_invoked_count: 1,
        builder_completed_count: 1,
        builder_failed_count: 0,
        builder_result: nil,
        exception: nil
      )
    end

    def with_activity_trigger_stub
      original = ActivityEvaluationTrigger.method(:call)
      result = successful_trigger_result
      ActivityEvaluationTrigger.define_singleton_method(:call) { |**| result }
      yield
    ensure
      ActivityEvaluationTrigger.define_singleton_method(:call, original)
    end
  end
end
