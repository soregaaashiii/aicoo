module Aicoo
  module Lovable
    class PipelineDiagnosisRefresher
      def self.call(generation_run:, source:)
        new(generation_run:, source:).call
      end

      def initialize(generation_run:, source:)
        @generation_run = generation_run
        @source = source
      end

      def call
        return unless lovable_pipeline?

        business = Business.find_by(id: metadata["business_id"])
        landing_page = BusinessPrototype.find_by(id: metadata["landing_page_prototype_id"])
        return unless business

        task = AutoRevisionTask.find_by(id: metadata["auto_revision_task_id"])
        analytics_site = AicooAnalyticsSite.where(business:).recent.first
        learning_snapshot = if landing_page
          AicooDataSnapshot
            .where(source_type: "landing_page_analytics", source_id: landing_page.id)
            .recent
            .first
        end
        webhook_configuration = GithubWebhookConfiguration.new
        webhook_diagnostics = webhook_configuration.diagnostics
        cloudflare_configuration = Aicoo::CloudflarePages::Configuration.new
        overview = PipelineOverview.new(
          generation_run:,
          landing_page:,
          task:,
          business:,
          analytics_site:,
          learning_snapshot:,
          webhook_diagnostics:,
          cloudflare_configuration:
        )
        connection_statuses = %w[ga4 gsc].index_with do |source_key|
          Aicoo::BusinessConnectionStatus.new(business, source_key:).call
        end
        result = PipelineDiagnosis.new(
          overview:,
          business:,
          landing_page:,
          generation_run:,
          analytics_site:,
          connection_statuses:,
          webhook_configuration:,
          webhook_diagnostics:,
          cloudflare_configuration:
        ).call
        PipelineDiagnosisSnapshot.write!(generation_run:, result:, source:)
      end

      private

      attr_reader :generation_run, :source

      def metadata
        @metadata ||= generation_run.metadata.to_h
      end

      def lovable_pipeline?
        generation_run.generation_type == "lp_generation" &&
          metadata["pipeline"] == VersionRepository::PIPELINE_KEY
      end
    end
  end
end
