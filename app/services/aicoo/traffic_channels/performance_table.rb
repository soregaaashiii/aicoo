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
        aggregate = aggregates_by_channel.fetch(channel.key, {})
        revenue = aggregate.fetch(:revenue_yen, 0)
        cost = aggregate.fetch(:cost_yen, 0)
        sessions = aggregate.fetch(:sessions, 0)
        clicks = aggregate.fetch(:clicks, 0)
        conversions = aggregate.fetch(:conversions, 0)
        successful = aggregate.fetch(:successful, 0)
        total = aggregate.fetch(:total, 0)
        profile = profiles_by_source[channel.key] || DataSourceCostProfile.new(
          DataSourceCostProfile::SOURCE_DEFINITIONS.fetch(channel.key, {}).merge(source_key: channel.key)
        )
        Row.new(
          channel_key: channel.key,
          label: channel.label,
          sessions:,
          clicks:,
          conversions:,
          revenue_yen: revenue,
          cost_yen: cost,
          hours: aggregate.fetch(:hours_spent, 0),
          roi: cost.to_i.positive? ? revenue.to_d / cost.to_d : nil,
          expected_value_yen: profile.average_expected_profit_yen.to_i,
          success_rate: total.positive? ? successful.to_d / total : 0.to_d,
          inflow_count: sessions.to_i.positive? ? sessions : clicks
        )
      end

      def aggregates_by_channel
        @aggregates_by_channel ||= TrafficChannelRun
          .where(channel_key: Registry.keys, ran_at: 30.days.ago.beginning_of_day..Time.current)
          .group(:channel_key)
          .pluck(
            :channel_key,
            Arel.sql("COALESCE(SUM(revenue_yen), 0)"),
            Arel.sql("COALESCE(SUM(cost_yen), 0)"),
            Arel.sql("COALESCE(SUM(sessions), 0)"),
            Arel.sql("COALESCE(SUM(clicks), 0)"),
            Arel.sql("COALESCE(SUM(conversions), 0)"),
            Arel.sql("COALESCE(SUM(hours_spent), 0)"),
            Arel.sql("SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END)"),
            Arel.sql("COUNT(*)")
          )
          .to_h do |channel_key, revenue, cost, sessions, clicks, conversions, hours, successful, total|
            [
              channel_key,
              {
                revenue_yen: revenue,
                cost_yen: cost,
                sessions: sessions,
                clicks: clicks,
                conversions: conversions,
                hours_spent: hours,
                successful: successful,
                total: total
              }
            ]
          end
      end

      def profiles_by_source
        @profiles_by_source ||= DataSourceCostProfile.where(source_key: Registry.keys).index_by(&:source_key)
      end
    end
  end
end
