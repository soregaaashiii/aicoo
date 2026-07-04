module Aicoo
  module IdeaPipeline
    class BusinessLinker
      def initialize(item)
        @item = item
      end

      def call
        item.transaction do
          business = existing_business || create_business!
          item.update!(business:) if item.business != business
          landing_page.update!(business:) if landing_page && landing_page.business != business
          business
        end
      end

      private

      attr_reader :item

      def existing_business
        item.business ||
          landing_page&.business ||
          Business.real_businesses.find_by(source: "idea_pipeline", idea_id: item.id) ||
          Business.real_businesses.find_by(name: business_name)
      end

      def create_business!
        Business.create!(
          name: business_name,
          description: business_description,
          category: business_category,
          status: "launched",
          source: "idea_pipeline",
          idea_id: item.id,
          created_by_aicoo: true,
          launched: true,
          daily_run_enabled: true,
          serp_enabled: true,
          auto_revision_mode: "automatic",
          auto_deploy_mode: "approval",
          auto_build_enabled: true,
          auto_build_requires_approval: false,
          auto_build_risk_level: "low",
          new_lp_auto_deploy_enabled: true
        ).tap { |business| Aicoo::NewBusinessAutomationDefaults.apply!(business) }
      end

      def landing_page
        @landing_page ||= item.aicoo_lab_landing_page
      end

      def experiment
        @experiment ||= landing_page&.aicoo_lab_experiment || item.aicoo_lab_experiment
      end

      def business_name
        landing_page&.public_headline.presence ||
          item.title.presence ||
          experiment&.title.presence ||
          "Idea Pipeline Business ##{item.id}"
      end

      def business_description
        landing_page&.public_subheadline.presence ||
          item.short_description.presence ||
          item.problem.presence ||
          experiment&.description.presence ||
          "Idea Pipelineから作成されたBusinessです。"
      end

      def business_category
        experiment&.market_category.presence ||
          experiment&.experiment_type.presence ||
          item.metadata.to_h["category"].presence ||
          "idea_pipeline"
      end
    end
  end
end
