module Aicoo
  module LpIntegration
    class LandingPageImprovementBatchAnalyzer
      Result = Data.define(:business_count, :landing_page_count, :analyzed_count, :candidate_count, :task_count, :skipped_count, :failed_count, :candidate_ids, :task_ids, :errors)

      def self.call
        new.call
      end

      def call
        stats = empty_stats
        target_businesses.find_each do |business|
          analyze_business(business, stats)
        end
        Result.new(**stats)
      end

      private

      def target_businesses
        Business.where(id: BusinessPrototype.active.external_landing_pages.select(:business_id))
      end

      def analyze_business(business, stats)
        landing_pages = business.business_prototypes.active.external_landing_pages.select do |landing_page|
          landing_page.landing_page_public_status == "published" &&
            (landing_page.landing_page_url.present? || landing_page.landing_page_ga4_path.present?)
        end
        return if landing_pages.empty?

        stats[:business_count] += 1
        stats[:landing_page_count] += landing_pages.size
        snapshots = Aicoo::Lovable::LandingPageAnalyticsReader.latest_snapshots_for(business)
        landing_pages.each { |landing_page| analyze_landing_page(business, landing_page, snapshots, stats) }
      end

      def analyze_landing_page(business, landing_page, snapshots, stats)
        result = LandingPageImprovementAnalyzer.new(business:, landing_page:, snapshots:).call
        stats[:analyzed_count] += 1
        if result.candidate
          stats[:candidate_count] += 1
          stats[:candidate_ids] << result.candidate.id
          create_improvement_task(business, landing_page, snapshots, result, stats)
        else
          stats[:skipped_count] += 1
        end
      rescue StandardError => e
        stats[:failed_count] += 1
        stats[:errors] << "LP ##{landing_page.id}: #{e.class}: #{e.message}"
        Rails.logger.warn("[LandingPageImprovementBatchAnalyzer] business_id=#{business.id} landing_page_id=#{landing_page.id} error=#{e.class}: #{e.message}")
      end

      def create_improvement_task(business, landing_page, snapshots, analysis, stats)
        return if analysis.candidate.final_expected_value_yen.to_d < minimum_expected_profit_yen
        return if landing_page.landing_page_repository_url.blank?

        flow = LandingPageImprovementFlow.new(
          business:,
          landing_page:,
          snapshots:,
          analysis:
        ).call
        return unless flow.created

        stats[:task_count] += 1
        stats[:task_ids] << flow.task.id
      end

      def minimum_expected_profit_yen
        @minimum_expected_profit_yen ||= AicooAutoRevisionSetting.current.minimum_final_score.to_d
      end

      def empty_stats
        {
          business_count: 0,
          landing_page_count: 0,
          analyzed_count: 0,
          candidate_count: 0,
          task_count: 0,
          skipped_count: 0,
          failed_count: 0,
          candidate_ids: [],
          task_ids: [],
          errors: []
        }
      end
    end
  end
end
