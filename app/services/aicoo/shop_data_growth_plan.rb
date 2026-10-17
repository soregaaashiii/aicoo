module Aicoo
  class ShopDataGrowthPlan
    METRIC_RULE = "early_shop_data_shortage".freeze
    BENCHMARK_COUNT = 80
    MINIMUM_ADD_COUNT = 30
    MAXIMUM_ADD_COUNT = 150

    attr_reader :business_name, :initial_count, :completed_count

    def self.for_candidate(candidate)
      metadata = candidate.metadata.to_h
      return unless metadata["metric_rule"] == METRIC_RULE

      progress = metadata.fetch("shop_data_growth_progress", {}).to_h
      initial_count = progress["initial_count"] || metadata["initial_count"] ||
        metadata.dig("evidence", "current_value") || metadata["current_value"] || 0
      target_count = progress["target_count"] || metadata["target_amount"] ||
        metadata.dig("evidence", "target_amount")
      completed_count = progress["completed_count"] || 0

      new(
        business_name: candidate.business&.name.presence || "対象Business",
        current_count: initial_count,
        target_count:,
        completed_count:
      )
    end

    def initialize(business_name:, current_count:, target_count: nil, completed_count: 0)
      @business_name = business_name
      @initial_count = [ current_count.to_i, 0 ].max
      @target_count = target_count.presence&.to_i
      @completed_count = [ completed_count.to_i, 0 ].max
    end

    def add_count
      @add_count ||= @target_count || [ [ BENCHMARK_COUNT - initial_count, MINIMUM_ADD_COUNT ].max, MAXIMUM_ADD_COUNT ].min
    end

    def current_count
      initial_count + completed_count
    end

    def benchmark_count
      initial_count + add_count
    end

    def remaining_count
      [ add_count - completed_count, 0 ].max
    end

    def completed?
      remaining_count.zero?
    end

    def title
      "#{business_name}の優先エリアに店舗データを#{add_count}件追加する"
    end

    def target_label
      "優先エリアの店舗追加（進捗 #{completed_count}/#{add_count}件・現在#{current_count}件 → 目標#{benchmark_count}件）"
    end

    def owner_next_step
      return "目標の店舗データ#{add_count}件を追加済み" if completed?

      "優先エリアの店舗データを残り#{remaining_count}件追加する"
    end

    def reason
      "候補開始後のShop作成Activityは#{completed_count}/#{add_count}件です。残り#{remaining_count}件を追加して目標#{benchmark_count}件まで増やします。"
    end

    def expected_effect
      "優先エリアの検索流入と回遊の受け皿を#{add_count}店舗分増やす"
    end

    def evidence
      {
        "source" => %w[activity_log internal],
        "issue_type" => METRIC_RULE,
        "target_identifier" => target_label,
        "current_value" => current_count,
        "benchmark_value" => benchmark_count,
        "target_amount" => add_count,
        "completed_amount" => completed_count,
        "remaining_amount" => remaining_count,
        "target_unit" => "件",
        "reason" => reason,
        "expected_effect" => expected_effect
      }
    end

    def execution_units
      [ {
        "label" => owner_next_step,
        "target_type" => "shop_data",
        "target_identifier" => target_label,
        "target_amount" => add_count,
        "estimated_minutes" => 60,
        "reason" => reason
      } ]
    end

    def metadata
      {
        "target" => target_label,
        "target_type" => "shop_data",
        "target_url_or_identifier" => target_label,
        "target_amount" => add_count,
        "target_unit" => "件",
        "initial_count" => initial_count,
        "current_value" => current_count,
        "benchmark_value" => benchmark_count,
        "completed_amount" => completed_count,
        "remaining_amount" => remaining_count,
        "concrete_task" => title,
        "owner_next_step" => owner_next_step,
        "execution_mode" => "data_operation",
        "execution_units" => execution_units,
        "completion_criteria" => [
          "優先エリアが1つ記録されている",
          "店舗データが#{add_count}件追加されている",
          "重複除外件数と未確認項目が記録されている"
        ],
        "evidence" => evidence
      }
    end
  end
end
