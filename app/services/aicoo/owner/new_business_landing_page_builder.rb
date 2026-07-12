module Aicoo
  module Owner
    class NewBusinessLandingPageBuilder
      def initialize(action_candidate)
        @action_candidate = action_candidate
      end

      def call
        raise ArgumentError, "Business化してからLPを作成してください。" unless business
        raise ArgumentError, "削除済みBusinessにはLPを作成できません。" if business.deleted?

        existing = business.aicoo_lab_landing_pages.order(updated_at: :desc).first
        return existing if existing

        AicooLabExperiment.transaction do
          experiment = AicooLabExperiment.create!(experiment_attributes)
          experiment.create_aicoo_lab_landing_page!(landing_page_attributes)
        end
      end

      private

      attr_reader :action_candidate

      def business
        @business ||= action_candidate.business ||
                      Business.find_by(id: action_candidate.metadata.to_h.dig("business_promotion", "business_id"))
      end

      def metadata
        @metadata ||= action_candidate.metadata.to_h
      end

      def experiment_attributes
        {
          title: title,
          description: description,
          experiment_type: "lp",
          market_category: business.category.presence || metadata["source_query"].presence || "new_business",
          acquisition_channel: "seo",
          status: "draft",
          approval_status: "not_required",
          expected_90d_profit_yen: action_candidate.expected_profit_yen.to_i,
          success_probability: action_candidate.success_probability.to_d.clamp(0, 0.85),
          budget_yen: action_candidate.cost_yen.to_i,
          estimated_work_minutes: (action_candidate.expected_hours.to_d * 60).to_i,
          assumed_price_yen: assumed_price_yen,
          lp_word_count: 900,
          cta_count: 1,
          notes: "Owner New Business Pipeline / ActionCandidate ##{action_candidate.id}",
          created_by: "owner_new_business_pipeline"
        }
      end

      def landing_page_attributes
        {
          business:,
          headline: public_copy(metadata["lp_headline"].presence || metadata["business_name"].presence || title),
          subheadline: public_copy(metadata["lp_subheadline"].presence || description),
          body: body,
          cta_text: public_copy(metadata["cta_text"].presence || "事前登録する"),
          assumed_price_yen: assumed_price_yen,
          published_slug: unique_slug,
          seo_title: public_copy(metadata["seo_title"].presence || title),
          seo_description: public_copy(metadata["seo_description"].presence || description),
          og_title: public_copy(metadata["seo_title"].presence || title),
          og_description: public_copy(metadata["seo_description"].presence || description),
          notes: "ActionCandidate ID: #{action_candidate.id}",
          status: "draft",
          public_status: "draft",
          generation_source: "candidate_conversion"
        }
      end

      def title
        metadata["business_name"].presence || metadata["service_name"].presence || action_candidate.title
      end

      def description
        metadata["problem"].presence || action_candidate.description.presence || business.description
      end

      def body
        public_copy(<<~BODY.strip)
          #{description}

          こんな方におすすめ:
          #{metadata["target_customer"].presence || metadata["target_user"].presence || "課題をすぐ解決したい方"}

          解決できること:
          #{metadata["lp_idea"].presence || metadata["landing_page_idea"].presence || title}

          まず確認できる内容:
          #{metadata["validation_method"].presence || "登録後、準備ができ次第ご案内します。"}

          料金の考え方:
          #{metadata["revenue_model"].presence || "初期検証後に正式な料金をご案内します。"}
        BODY
      end

      def assumed_price_yen
        metadata["assumed_price_yen"].to_i.positive? ? metadata["assumed_price_yen"].to_i : 9_800
      end

      def public_copy(value)
        AicooLabLandingPage.public_copy(value, fallback: "サービスのご案内")
      end

      def unique_slug
        base = title.to_s.parameterize.presence || "business-#{business.id}-lp"
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
