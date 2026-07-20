module Aicoo
  module Lovable
    class BuildUrlDiagnostic
      Row = Data.define(
        :business_id,
        :business_name,
        :prompt_generated,
        :build_url_generated,
        :prompt_version,
        :version,
        :preview_saved,
        :learning_status,
        :action_candidate_count,
        :launcher,
        :last_error
      )
      Result = Data.define(:rows, :summary)

      def initialize(business_id: nil)
        @business_id = business_id.presence&.to_i
      end

      def call
        rows = businesses.filter_map { |business| row_for(business) }
        Result.new(
          rows:,
          summary: {
            "business_count" => rows.length,
            "prompt_generated_count" => rows.count(&:prompt_generated),
            "build_url_generated_count" => rows.count(&:build_url_generated),
            "preview_saved_count" => rows.count(&:preview_saved),
            "learning_ready_count" => rows.count { |row| row.learning_status != "not_started" },
            "improvement_candidate_count" => rows.sum(&:action_candidate_count),
            "failed_count" => rows.count { |row| row.last_error.present? }
          }
        )
      end

      private

      attr_reader :business_id

      def businesses
        scope = Business.real_businesses
        scope = scope.where(id: business_id) if business_id
        scope.order(:id)
      end

      def row_for(business)
        repository = VersionRepository.new(business:)
        latest = repository.latest
        return unless latest

        metadata = latest.metadata.to_h
        published = repository.published
        learning = published&.metadata.to_h&.fetch("learning", {}) || {}
        Row.new(
          business_id: business.id,
          business_name: business.name,
          prompt_generated: latest.prompt.present?,
          build_url_generated: metadata["build_url"].present?,
          prompt_version: metadata["prompt_version"].presence || metadata["version_label"],
          version: metadata["version_label"],
          preview_saved: metadata["preview_url"].present?,
          learning_status: learning["measurement_status"].presence || "not_started",
          action_candidate_count: business.action_candidates.where(generation_source: "lp_learning").count,
          launcher: metadata["launcher"].presence || "build_with_url",
          last_error: latest.error_message
        )
      end
    end
  end
end
