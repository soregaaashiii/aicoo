require "test_helper"

module Aicoo
  class ShopDataGrowthPlanTest < ActiveSupport::TestCase
    test "turns a zero activity gap into a concrete eighty shop target" do
      plan = ShopDataGrowthPlan.new(business_name: "吸えログ", current_count: 0)

      assert_equal 80, plan.add_count
      assert_equal "吸えログの優先エリアに店舗データを80件追加する", plan.title
      assert_equal "優先エリアの店舗追加（直近30日 0件 → 目標80件）", plan.target_label
      assert_equal 80, plan.evidence.fetch("target_amount")
      assert_equal 0, plan.evidence.fetch("current_value")
      assert_equal 80, plan.evidence.fetch("benchmark_value")
      assert_equal "data_operation", plan.metadata.fetch("execution_mode")
    end

    test "uses the existing benchmark gap calculation" do
      plan = ShopDataGrowthPlan.new(business_name: "吸えログ", current_count: 12)

      assert_equal 68, plan.add_count
      assert_includes plan.owner_next_step, "68件追加"
    end

    test "recognizes legacy metric candidates without changing their saved metadata" do
      candidate = action_candidates(:nagazakicho_article)
      candidate.metadata = { "metric_rule" => ShopDataGrowthPlan::METRIC_RULE }

      plan = ShopDataGrowthPlan.for_candidate(candidate)

      assert_equal 80, plan.add_count
      assert_equal "吸えログの優先エリアに店舗データを80件追加する", plan.title
      assert_equal({ "metric_rule" => ShopDataGrowthPlan::METRIC_RULE }, candidate.metadata)
    end
  end
end
