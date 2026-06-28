module Aicoo
  module IdeaPipeline
    class LandingPageBuilder
      def initialize(item)
        @item = item
      end

      def call
        raise ArgumentError, "SERP合格前のためLP生成できません。" unless item.serp_passed?
        return item.aicoo_lab_landing_page if item.aicoo_lab_landing_page

        item.transaction do
          experiment = AicooLabExperiment.create!(experiment_attributes)
          landing_page = experiment.create_aicoo_lab_landing_page!(landing_page_attributes)
          item.update!(
            aicoo_lab_experiment: experiment,
            aicoo_lab_landing_page: landing_page,
            status: "lp_generated",
            current_stage: "lp",
            lp_generated_at: Time.current,
            metadata: item.metadata.to_h.merge(
              "lp_generated_at" => Time.current.iso8601,
              "lp_generation" => {
                "source" => "idea_pipeline",
                "serp_passed" => item.serp_passed?
              }
            )
          )
          landing_page
        end
      end

      private

      attr_reader :item

      def experiment_attributes
        {
          title: item.title,
          description: item.short_description,
          experiment_type: "lp",
          market_category: item.serp_snapshot.to_h["query"].presence || item.title,
          acquisition_channel: "seo",
          status: "draft",
          approval_status: "not_required",
          expected_90d_profit_yen: item.expected_profit_yen.to_i,
          success_probability: (item.final_score.to_d / 100).clamp(0, 0.85),
          budget_yen: 0,
          estimated_work_minutes: (item.development_hours.to_d * 60).to_i,
          assumed_price_yen: assumed_price_yen,
          lp_word_count: 900,
          cta_count: 1,
          notes: experiment_notes,
          created_by: "idea_pipeline"
        }
      end

      def landing_page_attributes
        {
          headline: item.lp_concept.presence || item.title,
          subheadline: item.short_description,
          body: landing_page_body,
          cta_text: cta_text,
          assumed_price_yen: assumed_price_yen,
          published_slug: unique_slug,
          seo_title: item.title,
          seo_description: item.short_description,
          og_title: item.title,
          og_description: item.short_description,
          notes: "Idea Pipeline ID: #{item.id}",
          status: "draft",
          public_status: "draft",
          generation_source: "manual"
        }
      end

      def landing_page_body
        <<~BODY.strip
          #{item.problem}

          想定ユーザー:
          #{item.target_user}

          提案する解決策:
          #{item.lp_concept}

          MVP案:
          #{item.mvp_concept}

          収益モデル:
          #{item.revenue_model}

          SERP検証:
          競合強度 #{item.serp_snapshot.to_h["competition_strength"] || "-"} / 市場性 #{item.serp_snapshot.to_h["market_signal"] || "-"} / 差別化 #{item.serp_snapshot.to_h["differentiation_score"] || "-"}

          まずはLPで反応を測定し、PV・CTA・滞在・検索流入からMVP開発判断を行います。
        BODY
      end

      def experiment_notes
        [
          "Idea Pipeline ID: #{item.id}",
          "SERP query: #{item.serp_snapshot.to_h['query']}",
          "Final score: #{item.final_score}",
          "Expected profit: #{item.expected_profit_yen}",
          "MVP: #{item.mvp_concept}"
        ].compact_blank.join("\n")
      end

      def cta_text
        "事前登録する"
      end

      def assumed_price_yen
        9_800
      end

      def unique_slug
        base = item.title.to_s.parameterize.presence || "idea-#{item.id}"
        candidate = base
        suffix = 2

        while AicooLabLandingPage.where(published_slug: candidate).exists? ||
              AicooLabLandingPageSlugHistory.where(slug: candidate).exists?
          candidate = "#{base}-#{suffix}"
          suffix += 1
        end
        candidate
      end
    end
  end
end
