module Aicoo
  class BusinessPlaybookSummary
    Result = Data.define(
      :total_businesses,
      :learned_businesses_count,
      :average_confidence,
      :low_confidence_businesses,
      :top_playbooks
    )

    def call
      playbooks = BusinessPlaybook.includes(:business).to_a
      Result.new(
        total_businesses: Business.count,
        learned_businesses_count: playbooks.count(&:learned?),
        average_confidence: average(playbooks.map(&:confidence_score)),
        low_confidence_businesses: Business.includes(:business_playbook).select { |business| business.business_playbook.nil? || business.business_playbook.confidence_score.to_d < 40 }.first(10),
        top_playbooks: playbooks.sort_by { |playbook| -playbook.confidence_score.to_d }.first(5)
      )
    end

    private

    def average(values)
      values = values.compact.map(&:to_d)
      return 0.to_d if values.empty?

      values.sum / values.size
    end
  end
end
