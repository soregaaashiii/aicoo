module Aicoo
  module LpIntegration
    class LandingPageAnalyzer
      LOOKBACK_DAYS = 90
      Result = Data.define(:landing_page, :payload)

      def initialize(business:, landing_page:, snapshots: nil, activity_logs: nil, revenue_events: nil, captured_at: Time.current)
        @business = business
        @landing_page = landing_page
        @snapshots = snapshots || Aicoo::Lovable::LandingPageAnalyticsReader.latest_snapshots_for(business)
        @activity_logs = activity_logs
        @revenue_events = revenue_events
        @captured_at = captured_at
      end

      def call
        validate!
        started_at = captured_at - LOOKBACK_DAYS.days
        analytics = Aicoo::Lovable::LandingPageAnalyticsReader.new(
          business:,
          started_at:,
          ended_at: captured_at,
          target_paths: target_paths,
          snapshots:
        ).call
        activity = LandingPageActivityReader.new(
          business:,
          landing_page:,
          started_at:,
          ended_at: captured_at,
          activity_logs:,
          revenue_events:
        ).call
        learning = LandingPageLearningBuilder.new(
          business:,
          landing_page:,
          snapshots:,
          activity_logs:,
          revenue_events:
        ).call
        sessions = analytics.ga4["sessions"].to_i
        improvements = improvement_candidates
        evaluated_learning = learning if learning&.fetch("status", nil) == "evaluated"

        payload = {
          "record_type" => "business_prototype_landing_page_analytics",
          "schema_version" => 1,
          "business_id" => business.id,
          "campaign_id" => landing_page.business_campaign_id,
          "landing_page_id" => landing_page.id,
          "landing_page_name" => landing_page.landing_page_name,
          "landing_page_url" => landing_page.landing_page_cloudflare_url,
          "page_path" => landing_page.landing_page_ga4_path,
          "public_status" => landing_page.landing_page_public_status,
          "measurement_started_at" => started_at.iso8601,
          "measurement_ended_at" => captured_at.iso8601,
          "ga4" => analytics.ga4,
          "gsc" => analytics.gsc,
          "activity" => activity.to_h.stringify_keys,
          "evaluation" => {
            "expected_profit_yen" => expected_profit_yen(improvements),
            "actual_profit_yen" => activity.profit_yen,
            "conversion_rate" => sessions.positive? ? (analytics.ga4["conversions"].to_d / sessions).round(6).to_f : nil,
            "inquiry_count" => activity.inquiries,
            "ctr" => analytics.gsc["ctr"],
            "average_position" => analytics.gsc["average_position"],
            "improvement_count" => improvement_history.size,
            "improvement_success_rate" => improvement_success_rate(learning),
            "win_rate" => landing_page.landing_page_ab_test["win_rate"],
            "last_improvement_at" => improvement_history.first&.dig(:occurred_at)&.iso8601,
            "ab_status" => landing_page.landing_page_ab_test["status"].presence || "inactive",
            "improvement_candidate_count" => improvements.size
          },
          "cloudflare" => {
            "published_at" => landing_page.landing_page_last_published_at&.iso8601,
            "public_url" => landing_page.landing_page_cloudflare_url,
            "deploy_status" => landing_page.metadata.to_h["cloudflare_deploy_status"],
            "last_deploy_at" => landing_page.metadata.to_h["last_deploy_at"],
            "last_push_at" => landing_page.landing_page_last_push_at&.iso8601
          },
          "learning" => learning,
          "mvp_planner_facts" => {
            "conversion_rate" => sessions.positive? ? (analytics.ga4["conversions"].to_d / sessions).round(6).to_f : nil,
            "inquiries" => activity.inquiries,
            "contracts" => activity.contracts,
            "revenue_yen" => activity.revenue_yen,
            "profit_yen" => activity.profit_yen,
            "learning_confidence" => evaluated_learning&.fetch("confidence", nil)
          },
          "captured_at" => captured_at.iso8601
        }.compact

        Result.new(landing_page:, payload:)
      end

      private

      attr_reader :business, :landing_page, :snapshots, :activity_logs, :revenue_events, :captured_at

      def validate!
        return if landing_page.business_id == business.id && landing_page.external_landing_page?

        raise ArgumentError, "このBusinessのLPではありません。"
      end

      def target_paths
        [
          landing_page.landing_page_url,
          landing_page.landing_page_cloudflare_url,
          landing_page.landing_page_ga4_path,
          landing_page.metadata.to_h["gsc_url"]
        ].compact
      end

      def improvement_candidates
        @improvement_candidates ||= business.action_candidates.where(generation_source: "lp_learning").to_a.select do |candidate|
          candidate.metadata.to_h["landing_page_id"].to_i == landing_page.id ||
            task_variant_ids(candidate).include?(landing_page.id)
        end
      end

      def task_variant_ids(candidate)
        candidate.auto_revision_tasks.map { |task| task.metadata.to_h["landing_page_prototype_id"].to_i }
      end

      def improvement_history
        @improvement_history ||= LandingPageImprovementHistory.new(business).call.select do |row|
          row[:landing_page_id] == landing_page.id ||
            improvement_candidates.any? { |candidate| candidate.id == row[:action_candidate_id] }
        end
      end

      def expected_profit_yen(candidates)
        stored = landing_page.metadata.to_h["expected_profit_yen"].to_i
        [ stored, candidates.map(&:final_expected_value_yen).compact.map(&:to_i).max.to_i ].max
      end

      def improvement_success_rate(current_learning)
        learning_rows = AicooDataSnapshot.where(source_type: "landing_page_analytics", source_id: landing_page.id).recent.filter_map do |snapshot|
          learning = snapshot.payload.to_h["learning"].to_h
          learning if learning["status"] == "evaluated"
        end
        learning_rows << current_learning if current_learning&.fetch("status", nil) == "evaluated"
        rows = learning_rows.uniq { |row| [ row["action_candidate_id"], row["evaluation_started_at"] ] }
        return if rows.empty?

        (rows.count { |row| row["success"] == true }.to_d / rows.length).round(4).to_f
      end
    end
  end
end
