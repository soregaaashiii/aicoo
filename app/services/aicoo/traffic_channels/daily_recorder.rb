module Aicoo
  module TrafficChannels
    class DailyRecorder
      Result = Data.define(:recorded_count, :skipped_count)

      def self.record!(daily_run:)
        new(daily_run:).record!
      end

      def initialize(daily_run:)
        @daily_run = daily_run
      end

      def record!
        recorded_count = record_serp_runs
        Result.new(recorded_count:, skipped_count: Registry.keys.size - 1)
      end

      private

      attr_reader :daily_run

      def record_serp_runs
        analyses = SerpAnalysis.where(analyzed_at: daily_run.target_date.all_day).includes(:business)
        analyses.group_by(&:business_id).sum do |business_id, rows|
          business = rows.first.business
          failed_count = rows.count(&:failed?)
          status = failed_count.positive? ? "warning" : "success"
          TrafficChannelRun.create!(
            business:,
            channel_key: "serp",
            status:,
            source: "daily_run",
            ran_at: daily_run.finished_at || Time.current,
            clicks: rows.sum { |analysis| analysis.result_count.to_i },
            conversions: 0,
            revenue_yen: 0,
            cost_yen: estimated_serp_cost(rows.size),
            hours_spent: 0,
            error_message: rows.find(&:failed?)&.error_message,
            metadata: {
              aicoo_daily_run_id: daily_run.id,
              analysis_count: rows.size,
              failed_count:,
              keywords: rows.map(&:keyword).first(20)
            }
          )
          1
        end
      end

      def estimated_serp_cost(count)
        profile = DataSourceCostProfile.for_source("serp")
        (profile.average_cost_yen.to_d * count).round.to_i
      end
    end
  end
end
