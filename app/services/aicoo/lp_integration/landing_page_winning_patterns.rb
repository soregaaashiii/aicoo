module Aicoo
  module LpIntegration
    class LandingPageWinningPatterns
      def initialize(business: nil)
        @business = business
      end

      def call
        {
          "business" => aggregate(learning_rows.select { |row| row.fetch("business_id").to_i == business&.id }),
          "global" => aggregate(learning_rows)
        }
      end

      private

      attr_reader :business

      def learning_rows
        @learning_rows ||= AicooDataSnapshot.where(source_type: "landing_page_analytics").recent.filter_map do |snapshot|
          payload = snapshot.payload.to_h
          learning = payload["learning"].to_h
          next unless learning["status"] == "evaluated"

          learning.merge(
            "business_id" => payload["business_id"],
            "landing_page_id" => payload["landing_page_id"]
          )
        end.uniq { |row| [ row["action_candidate_id"], row["evaluation_started_at"] ] }
      end

      def aggregate(rows)
        rows.group_by { |row| row["improvement_type"].presence || "unknown" }.filter_map do |type, samples|
          successes = samples.count { |row| row["success"] == true }
          confidence = average(samples.filter_map { |row| decimal(row["confidence"]) })
          profit_delta = average(samples.filter_map { |row| delta(row, "profit_yen") })
          cvr_delta = average(samples.filter_map { |row| delta(row, "conversion_rate") })
          ctr_delta = average(samples.filter_map { |row| delta(row, "ctr") })
          {
            "improvement_type" => type,
            "sample_count" => samples.length,
            "success_rate" => (successes.to_d / samples.length).round(4).to_f,
            "average_profit_delta_yen" => profit_delta&.round,
            "average_conversion_rate_delta" => cvr_delta&.round(6)&.to_f,
            "average_ctr_delta" => ctr_delta&.round(6)&.to_f,
            "confidence" => confidence&.round(2)&.to_f
          }
        end.sort_by { |row| [ -row.fetch("success_rate"), -row.fetch("average_profit_delta_yen").to_i, row.fetch("improvement_type") ] }
      end

      def delta(row, metric)
        decimal(row.dig("deltas", metric, "delta"))
      end

      def decimal(value)
        return if value.blank?

        BigDecimal(value.to_s)
      rescue ArgumentError
        nil
      end

      def average(values)
        return if values.empty?

        values.sum / values.length
      end
    end
  end
end
