module Aicoo
  class BusinessRegistrationAnalysisJob < ApplicationJob
    queue_as :default

    def perform(business_id, prototype_id = nil)
      business = Business.find(business_id)
      prototype = BusinessPrototype.find_by(id: prototype_id, business:)
      Aicoo::BusinessRegistrationAnalyzer.new(business:, prototype:).call
    rescue ActiveRecord::RecordNotFound
      nil
    rescue StandardError => e
      prototype&.update(
        analysis_status: "failed",
        analyzed_at: Time.current,
        metadata: prototype.metadata.to_h.merge(
          "analysis_error" => "#{e.class}: #{e.message}",
          "analysis_failed_at" => Time.current.iso8601
        )
      )
      Rails.logger.error(
        "[BusinessRegistrationAnalysisJob] business_id=#{business_id} prototype_id=#{prototype_id} failed #{e.class}: #{e.message}"
      )
    end
  end
end
