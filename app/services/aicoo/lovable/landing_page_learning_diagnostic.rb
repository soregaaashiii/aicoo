module Aicoo
  module Lovable
    class LandingPageLearningDiagnostic
      Row = Data.define(
        :business_id,
        :business_name,
        :current_version,
        :best_version,
        :cvr,
        :roi,
        :confidence,
        :learning_status,
        :candidate_count,
        :improvements,
        :lovable_sent_count,
        :published_version_count,
        :benchmark_source,
        :skip_reason
      )
      Result = Data.define(:rows, :summary)

      def initialize(business_id: nil)
        @business_id = business_id.presence
      end

      def call
        rows = businesses.filter_map { |business| diagnose_business(business) }
        Result.new(rows:, summary: summary(rows))
      end

      private

      attr_reader :business_id

      def businesses
        scope = Business.real_businesses
        business_id ? scope.where(id: business_id) : scope
      end

      def diagnose_business(business)
        repository = VersionRepository.new(business:)
        return if repository.published_versions.empty?

        analysis = LandingPageImprovementAnalyzer.new(business:, generation_run: repository.published, persist: false).call
        comparison = analysis.comparison
        candidate_scope = business.action_candidates.where(generation_source: LandingPageImprovementAnalyzer::GENERATION_SOURCE)
        candidate_ids = candidate_scope.pluck(:id)
        sent_count = repository.all.count do |run|
          run.metadata.to_h["request_type"] == "revision" && run.metadata.to_h["action_candidate_id"].to_i.in?(candidate_ids)
        end
        Row.new(
          business_id: business.id,
          business_name: business.name,
          current_version: analysis.generation_run.metadata.to_h["version"],
          best_version: comparison.best&.run&.metadata.to_h&.dig("version"),
          cvr: analysis.learning["cvr"],
          roi: analysis.learning["roi"],
          confidence: analysis.learning["confidence"],
          learning_status: analysis.analysis_status,
          candidate_count: candidate_scope.count,
          improvements: analysis.improvements.map { |item| item.to_h.slice(:type, :reason) },
          lovable_sent_count: sent_count,
          published_version_count: repository.published_versions.length,
          benchmark_source: comparison.benchmark_source,
          skip_reason: analysis.skip_reason
        )
      end

      def summary(rows)
        {
          "business_count" => rows.length,
          "published_version_count" => rows.sum(&:published_version_count),
          "learning_ready_count" => rows.count { |row| row.learning_status.in?(%w[healthy improvement_found]) },
          "improvement_candidate_count" => rows.sum(&:candidate_count),
          "lovable_sent_count" => rows.sum(&:lovable_sent_count),
          "businesses_with_best_version" => rows.count { |row| row.best_version.present? }
        }
      end
    end
  end
end
