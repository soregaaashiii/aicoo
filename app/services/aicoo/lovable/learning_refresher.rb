module Aicoo
  module Lovable
    class LearningRefresher
      def self.call(landing_page)
        return unless landing_page&.generation_source == "lovable" && landing_page.business

        repository = VersionRepository.new(business: landing_page.business, landing_page:)
        published = repository.published
        return unless published

        LearningSummary.new(business: landing_page.business, generation_run: published).call(persist: true)
      rescue StandardError => e
        Rails.logger.warn("[Lovable] LP learning refresh failed landing_page_id=#{landing_page&.id}: #{e.class}: #{e.message}")
      end
    end
  end
end
