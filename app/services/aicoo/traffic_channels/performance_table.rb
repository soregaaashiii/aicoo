module Aicoo
  module TrafficChannels
    class PerformanceTable
      Row = Data.define(
        :channel_key,
        :label,
        :sessions,
        :clicks,
        :conversions,
        :revenue_yen,
        :cost_yen,
        :hours,
        :roi,
        :expected_value_yen,
        :success_rate,
        :inflow_count
      )

      def self.call(limit: nil)
        new(limit:).call
      end

      def initialize(limit: nil)
        @limit = limit
      end

      def call
        rows = Registry.channels.map { |channel| row_for(channel) }
        rows.sort_by { |row| [ row.roi || -1, row.revenue_yen, row.inflow_count ] }.reverse.then do |sorted|
          limit ? sorted.first(limit) : sorted
        end
      end

      private

      attr_reader :limit

      def row_for(channel)
        scope = TrafficChannelRun.where(channel_key: channel.key, ran_at: 30.days.ago.beginning_of_day..Time.current)
        revenue = scope.sum(:revenue_yen)
        cost = scope.sum(:cost_yen)
        sessions = scope.sum(:sessions)
        clicks = scope.sum(:clicks)
        conversions = scope.sum(:conversions)
        successful = scope.successful.count
        total = scope.count
        Row.new(
          channel_key: channel.key,
          label: channel.label,
          sessions:,
          clicks:,
          conversions:,
          revenue_yen: revenue,
          cost_yen: cost,
          hours: scope.sum(:hours_spent),
          roi: cost.to_i.positive? ? revenue.to_d / cost.to_d : nil,
          expected_value_yen: DataSourceCostProfile.for_source(channel.key).average_expected_profit_yen.to_i,
          success_rate: total.positive? ? successful.to_d / total : 0.to_d,
          inflow_count: sessions.to_i.positive? ? sessions : clicks
        )
      end
    end
  end
end
