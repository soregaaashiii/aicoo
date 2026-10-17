module Aicoo
  class ShopDataGrowthPlan
    METRIC_RULE = "early_shop_data_shortage".freeze
    BENCHMARK_COUNT = 80
    MINIMUM_ADD_COUNT = 30
    MAXIMUM_ADD_COUNT = 150

    attr_reader :business_name, :current_count

    def self.for_candidate(candidate)
      metadata = candidate.metadata.to_h
      return unless metadata["metric_rule"] == METRIC_RULE

      current_count = metadata.dig("evidence", "current_value") || metadata["current_value"] || 0
      new(business_name: candidate.business&.name.presence || "対象Business", current_count:)
    end

    def initialize(business_name:, current_count:)
      @business_name = business_name
      @current_count = [ current_count.to_i, 0 ].max
    end

    def add_count
      @add_count ||= [ [ BENCHMARK_COUNT - current_count, MINIMUM_ADD_COUNT ].max, MAXIMUM_ADD_COUNT ].min
    end

    def title
      "#{business_name}の優先エリアに店舗データを#{add_count}件追加する"
    end

    def target_label
      "優先エリアの店舗追加（直近30日 #{current_count}件 → 目標#{BENCHMARK_COUNT}件）"
    end

    def owner_next_step
      "優先エリアを1つ決め、そのエリアの店舗データを#{add_count}件追加する"
    end

    def reason
      "直近30日のShop Activityが#{current_count}件のため、#{add_count}件追加して目標#{BENCHMARK_COUNT}件まで増やします。"
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
        "benchmark_value" => BENCHMARK_COUNT,
        "target_amount" => add_count,
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
        "current_value" => current_count,
        "benchmark_value" => BENCHMARK_COUNT,
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
