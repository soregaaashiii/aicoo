module Owner
  class OpportunitiesController < ApplicationController
    before_action :set_opportunity, only: %i[
      show
      review
      reject
      convert_to_candidate
      focus_review
      focus_reject
      focus_convert_to_candidate
    ]

    def index
      @opportunities = OpportunityDiscoveryItem.includes(:business, :action_candidate).top_ranked
      @opportunity_summary = Aicoo::OpportunityDiscoverySummary.new.call
      @opportunity_focus_queue = Aicoo::OpportunityFocusQueue.new.call
    end

    def show
      @discovery_source_summary = Aicoo::DiscoverySourcePerformanceReport.new.call.source_summaries.find do |summary|
        summary.source_type == @opportunity.source_type
      end
    end

    def focus
      @opportunity_focus_queue = Aicoo::OpportunityFocusQueue.new.call
      @focus_item = @opportunity_focus_queue.top_item
    end

    def new
      @opportunity = OpportunityDiscoveryItem.new(source_type: "owner_discovery", status: "new", opportunity_score: 50)
    end

    def create
      @opportunity = OpportunityDiscoveryItem.new(opportunity_params)

      if @opportunity.save
        redirect_to owner_opportunity_path(@opportunity), notice: "Opportunityを作成しました。"
      else
        render :new, status: :unprocessable_content
      end
    end

    def review
      @opportunity.update!(status: "reviewed")
      redirect_to owner_opportunity_path(@opportunity), notice: "Opportunityをreviewedにしました。"
    end

    def reject
      @opportunity.update!(status: "rejected")
      redirect_to owner_opportunities_path, notice: "Opportunityを却下しました。"
    end

    def convert_to_candidate
      candidate = @opportunity.convert_to_action_candidate!
      redirect_to candidate, notice: "OpportunityをActionCandidateへ変換しました。"
    end

    def focus_review
      @opportunity.update!(status: "reviewed")
      redirect_to focus_owner_opportunities_path, notice: "Opportunityをreviewedにしました。次のOpportunityを表示します。"
    end

    def focus_reject
      @opportunity.update!(status: "rejected")
      redirect_to focus_owner_opportunities_path, notice: "Opportunityを却下しました。次のOpportunityを表示します。"
    end

    def focus_convert_to_candidate
      @opportunity.convert_to_action_candidate!
      redirect_to focus_owner_opportunities_path, notice: "OpportunityをActionCandidateへ変換しました。次のOpportunityを表示します。"
    end

    private

    def set_opportunity
      @opportunity = OpportunityDiscoveryItem.find(params.expect(:id))
    end

    def opportunity_params
      params.expect(opportunity_discovery_item: [
        :title,
        :description,
        :source_type,
        :opportunity_score,
        :status,
        :business_id,
        metadata: {}
      ])
    end
  end
end
