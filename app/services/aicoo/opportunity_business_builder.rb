module Aicoo
  class OpportunityBusinessBuilder
    def initialize(opportunity)
      @opportunity = opportunity
    end

    def call
      return opportunity.business if opportunity.business

      business = Business.find_or_create_by!(name: business_name) do |record|
        record.status = "idea"
        record.description = business_description
      end

      opportunity.update!(
        business:,
        status: next_status,
        metadata: opportunity.metadata.to_h.merge(
          "new_service_candidate" => true,
          "business_created_from_opportunity" => true,
          "created_business_id" => business.id
        )
      )
      business
    end

    private

    attr_reader :opportunity

    def business_name
      opportunity.title.to_s.squish.presence || "New Service #{opportunity.id}"
    end

    def business_description
      [
        "Opportunity Discoveryから作成した新規サービス下書きです。",
        "",
        "元Opportunity:",
        opportunity.title,
        "",
        "概要:",
        opportunity.summary.presence || opportunity.description.presence || "-"
      ].join("\n")
    end

    def next_status
      opportunity.status.in?(%w[new pending]) ? "approved" : opportunity.status
    end
  end
end
