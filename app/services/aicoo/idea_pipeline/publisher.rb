module Aicoo
  module IdeaPipeline
    class Publisher
      def initialize(item)
        @item = item
      end

      def call
        raise ArgumentError, "LPが未生成です。" unless item.aicoo_lab_landing_page

        landing_page = item.aicoo_lab_landing_page
        landing_page.aicoo_lab_experiment.update!(status: "preview_ready", approval_status: "approved")
        landing_page.update!(status: "preview_ready")
        Aicoo::LandingPagePublicationService.publish!(landing_page)
        business = Aicoo::IdeaPipeline::BusinessLinker.new(item).call
        item.update!(
          status: "published",
          current_stage: "publish",
          published_at: landing_page.published_at || Time.current,
          business:,
          metadata: item.metadata.to_h.merge(
            "business_id" => business.id,
            "published_lp_slug" => landing_page.published_slug,
            "published_at" => Time.current.iso8601
          )
        )
        Aicoo::PipelineEngine.new(item).call
        item
      end

      private

      attr_reader :item
    end
  end
end
