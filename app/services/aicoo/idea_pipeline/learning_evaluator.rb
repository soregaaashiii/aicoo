module Aicoo
  module IdeaPipeline
    class LearningEvaluator
      def initialize(item)
        @item = item
      end

      def call
        landing_page = item.aicoo_lab_landing_page
        metrics = landing_page ? landing_page_metrics(landing_page) : empty_metrics
        updated_score = updated_expected_score(metrics)

        item.update!(
          status: "learning_evaluated",
          current_stage: "learning",
          final_score: updated_score,
          learning_evaluated_at: Time.current,
          learning_snapshot: metrics.merge(
            "updated_score" => updated_score.to_f,
            "evaluated_at" => Time.current.iso8601,
            "recommendation" => recommendation_for(metrics, updated_score)
          )
        )
        item
      end

      private

      attr_reader :item

      def landing_page_metrics(landing_page)
        views = landing_page.view_count
        cta_clicks = landing_page.cta_click_count
        signups = landing_page.signup_count
        {
          "pv" => views,
          "cta_clicks" => cta_clicks,
          "signups" => signups,
          "cta_rate" => rate(cta_clicks, views),
          "signup_rate" => rate(signups, views),
          "search_flow" => inferred_search_flow(landing_page)
        }
      end

      def empty_metrics
        {
          "pv" => 0,
          "cta_clicks" => 0,
          "signups" => 0,
          "cta_rate" => 0,
          "signup_rate" => 0,
          "search_flow" => 0
        }
      end

      def updated_expected_score(metrics)
        response_bonus = metrics["cta_rate"].to_d * 80 + metrics["signup_rate"].to_d * 120
        traffic_bonus = [ metrics["pv"].to_i / 50, 15 ].min
        search_bonus = [ metrics["search_flow"].to_i * 2, 20 ].min
        [ [ item.final_score.to_d + response_bonus + traffic_bonus + search_bonus, 0 ].max, 100 ].min.round(2)
      end

      def recommendation_for(metrics, score)
        return "develop" if score >= 80 && metrics["cta_clicks"].to_i.positive?
        return "continue_lp" if score >= 65
        return "improve" if metrics["pv"].to_i.positive?

        "end"
      end

      def inferred_search_flow(landing_page)
        return 0 unless BusinessMetricDaily.column_names.include?("metadata")

        BusinessMetricDaily.where("metadata ->> 'landing_page_id' = ?", landing_page.id.to_s).sum(:sessions)
      rescue ActiveRecord::StatementInvalid
        0
      end

      def rate(numerator, denominator)
        return 0 if denominator.to_i.zero?

        (numerator.to_d / denominator.to_d).round(4)
      end
    end
  end
end
