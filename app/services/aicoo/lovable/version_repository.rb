module Aicoo
  module Lovable
    class VersionRepository
      PIPELINE_KEY = "lovable".freeze

      def initialize(business: nil, landing_page: nil, landing_page_prototype: nil)
        @business = business
        @landing_page = landing_page
        @landing_page_prototype = landing_page_prototype
      end

      attr_reader :business, :landing_page, :landing_page_prototype

      def all
        @all ||= begin
          scope = AicooLabGenerationRun
            .where(generation_type: "lp_generation")
            .where("metadata ->> 'pipeline' = ?", PIPELINE_KEY)
          scope = scope.where("metadata ->> 'business_id' = ?", business.id.to_s) if business
          scope = scope.where("metadata ->> 'landing_page_id' = ?", landing_page.id.to_s) if landing_page
          if landing_page_prototype
            scope = scope.where(
              "metadata ->> 'landing_page_prototype_id' = ?",
              landing_page_prototype.id.to_s
            )
          end
          scope.recent.to_a
        end
      end

      def current
        successful.max_by { |run| [ version(run), run.created_at ] }
      end

      def published
        published_versions.max_by { |run| run.metadata.to_h.dig("publication", "published_at").to_s }
      end

      def published_versions
        all.select { |run| run.metadata.to_h.dig("publication", "published") == true }
           .sort_by { |run| run.metadata.to_h.dig("publication", "published_at").to_s }
      end

      def latest
        all.max_by(&:created_at)
      end

      def successful
        all.select { |run| run.status == "succeeded" && run.metadata.to_h["pipeline_status"] != "failed" }
      end

      def next_version
        all.map { |run| version(run) }.max.to_i + 1
      end

      def version(run)
        run.metadata.to_h["version"].to_i
      end

      def find(id)
        all.find { |run| run.id == id.to_i }
      end
    end
  end
end
