module Aicoo
  module TrafficChannels
    class ActionCandidateGenerator
      def self.call(channel_key:, business:)
        new(channel_key:, business:).call
      end

      def initialize(channel_key:, business:)
        @channel_key = channel_key.to_s
        @business = business
      end

      def call
        channel = Registry.find(channel_key)
        raise ArgumentError, "未対応の集客チャネルです: #{channel_key}" unless channel

        business.action_candidates.create!(
          title: "#{channel.label}の集客施策を見直す",
          description: "#{business.name}で#{channel.label}の成果・工数・費用を確認し、次に増やすか止めるか判断します。",
          action_type: action_type_for(channel_key),
          department: "revenue",
          generation_source: "traffic_channel",
          status: "idea",
          immediate_value_yen: DataSourceCostProfile.for_source(channel_key).average_expected_profit_yen.to_i,
          success_probability: 0.35,
          expected_hours: 1,
          cost_yen: DataSourceCostProfile.for_source(channel_key).average_cost_yen.to_i,
          evaluation_reason: "Traffic Channel Centerから生成しました。",
          execution_prompt: "#{business.name}の#{channel.label}について、流入・CV・Revenue・Cost・工数を確認し、改善または停止判断をしてください。",
          metadata: {
            source: "traffic_channel_center",
            channel_key:,
            channel_label: channel.label
          }
        )
      end

      private

      attr_reader :channel_key, :business

      def action_type_for(key)
        case key
        when "seo_article", "serp"
          "seo_improvement"
        when "small_ads"
          "sales"
        else
          "market_research"
        end
      end
    end
  end
end
