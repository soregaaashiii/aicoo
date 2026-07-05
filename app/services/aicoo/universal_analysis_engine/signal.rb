module Aicoo
  module UniversalAnalysisEngine
    Signal = Data.define(
      :business,
      :query,
      :page_path,
      :asset_label,
      :target_label,
      :target_type,
      :source,
      :impressions,
      :clicks,
      :ctr,
      :position,
      :sessions,
      :pageviews,
      :conversions,
      :conversion_events,
      :activity_count,
      :demand_score,
      :supply_score,
      :conversion_intent_score,
      :asset_match_score,
      :ga4_engagement_score,
      :work_cost,
      :roi_score,
      :expected_value_yen,
      :metadata
    ) do
      def to_h
        self.class.members.index_with { |member| public_send(member) }.except(:business)
      end
    end
  end
end
