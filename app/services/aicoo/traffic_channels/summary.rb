module Aicoo
  module TrafficChannels
    class Summary
      Result = Data.define(
        :health,
        :enabled_channel_count,
        :today_active_channel_count,
        :today_total_inflow_count,
        :today_conversion_count,
        :today_revenue_yen,
        :today_hours,
        :today_cost_yen,
        :today_roi,
        :stopped_channel_count,
        :best_channel,
        :worst_channel,
        :today_traffic_action_candidate_count
      )

      def self.call
        new.call
      end

      def call
        Result.new(
          health:,
          enabled_channel_count: enabled_profiles.count,
          today_active_channel_count: today_active_channel_count,
          today_total_inflow_count: today_runs.to_a.sum(&:inflow_count),
          today_conversion_count: today_runs.sum(:conversions),
          today_revenue_yen: today_runs.sum(:revenue_yen),
          today_hours: today_runs.sum(:hours_spent),
          today_cost_yen: today_runs.sum(:cost_yen),
          today_roi:,
          stopped_channel_count: stopped_channel_keys.count,
          best_channel: performance_rows.first,
          worst_channel: performance_rows.reverse.find { |row| row.inflow_count.positive? || row.cost_yen.positive? },
          today_traffic_action_candidate_count: today_traffic_candidates.count
        )
      end

      private

      def today_runs
        @today_runs ||= TrafficChannelRun.today
      end

      def today_serp_runs
        @today_serp_runs ||= SerpRun.today
      end

      def enabled_profiles
        @enabled_profiles ||= begin
          profiles = DataSourceCostProfile.where(source_key: Registry.keys).index_by(&:source_key)
          Registry.keys.select { |key| profiles[key]&.enabled? != false }
        end
      end

      def today_traffic_candidates
        @today_traffic_candidates ||= ActionCandidate.where(generation_source: "traffic_channel", created_at: Time.zone.today.all_day)
      end

      def today_roi
        cost = today_runs.sum(:cost_yen).to_d
        return nil if cost.zero?

        today_runs.sum(:revenue_yen).to_d / cost
      end

      def stopped_channel_keys
        failed = today_runs.failed.distinct.pluck(:channel_key)
        failed << "serp" if today_serp_runs.where(status: %w[failed partial_failed]).exists?
        disabled = DataSourceCostProfile.where(source_key: Registry.keys, enabled: false).pluck(:source_key)
        (failed + disabled).uniq
      end

      def today_active_channel_count
        keys = today_runs.distinct.pluck(:channel_key)
        keys << "serp" if today_serp_runs.exists?
        keys.uniq.count
      end

      def performance_rows
        @performance_rows ||= Aicoo::TrafficChannels::PerformanceTable.call(limit: Registry.keys.size)
      end

      def health
        return "Broken" if today_serp_runs.where(status: "failed").exists?
        return "Warning" if today_serp_runs.where(status: "partial_failed").exists?
        return "Broken" if today_runs.failed.exists?
        return "Warning" if stopped_channel_keys.any?

        "Healthy"
      end
    end
  end
end
