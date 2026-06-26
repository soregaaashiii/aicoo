module Owner
  class OpportunitiesController < ApplicationController
    before_action :set_opportunity, only: %i[
      show
      review
      approve
      reject
      create_business
      convert_to_candidate
      focus_approve
      focus_review
      focus_reject
      focus_create_business
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

    def approve
      previous_status = @opportunity.status
      @opportunity.update!(status: "approved")
      record_decision!("approve", "opportunity_detail", previous_status:)
      redirect_to owner_opportunity_path(@opportunity), notice: "Opportunityをapprovedにしました。"
    end

    def reject
      previous_status = @opportunity.status
      @opportunity.update!(status: "rejected")
      record_decision!("reject", "opportunity_detail", previous_status:)
      redirect_to owner_opportunities_path, notice: "Opportunityを却下しました。"
    end

    def create_business
      previous_status = @opportunity.status
      business = Aicoo::OpportunityBusinessBuilder.new(@opportunity).call
      record_decision!(
        "create_business",
        "opportunity_detail",
        previous_status:,
        metadata: { business_id: business.id }
      )
      redirect_to owner_opportunity_path(@opportunity), notice: "新規サービス下書き『#{business.name}』を作成しました。次にActionCandidate化できます。"
    end

    def convert_to_candidate
      previous_status = @opportunity.status
      candidate = @opportunity.convert_to_action_candidate!
      unless candidate
        redirect_to owner_opportunity_path(@opportunity), alert: @opportunity.practicality_reason.presence || "具体化が必要なためActionCandidate化しませんでした。"
        return
      end
      record_decision!(
        "convert",
        "opportunity_detail",
        previous_status:,
        metadata: { action_candidate_id: candidate.id }
      )
      redirect_to candidate, notice: "OpportunityをActionCandidateへ変換しました。"
    end

    def focus_review
      @opportunity.update!(status: "reviewed")
      redirect_to focus_owner_opportunities_path, notice: "Opportunityをreviewedにしました。次のOpportunityを表示します。"
    end

    def focus_approve
      previous_status = @opportunity.status
      @opportunity.update!(status: "approved")
      record_decision!("approve", "owner_focus", previous_status:)
      redirect_to owner_focus_path, notice: "Opportunityをapprovedにしました。"
    end

    def focus_reject
      previous_status = @opportunity.status
      @opportunity.update!(status: "rejected")
      record_decision!("reject", "owner_focus", previous_status:)
      redirect_to owner_focus_path, notice: "Opportunityを却下しました。"
    end

    def focus_create_business
      previous_status = @opportunity.status
      business = Aicoo::OpportunityBusinessBuilder.new(@opportunity).call
      record_decision!(
        "create_business",
        "owner_focus",
        previous_status:,
        metadata: { business_id: business.id }
      )
      redirect_to owner_focus_path, notice: "新規サービス下書き『#{business.name}』を作成しました。"
    end

    def focus_convert_to_candidate
      previous_status = @opportunity.status
      candidate = @opportunity.convert_to_action_candidate!
      unless candidate
        redirect_to owner_focus_path, alert: @opportunity.practicality_reason.presence || "具体化が必要なためActionCandidate化しませんでした。"
        return
      end
      record_decision!(
        "convert",
        "owner_focus",
        previous_status:,
        metadata: { action_candidate_id: candidate.id }
      )
      redirect_to candidate, notice: "OpportunityをActionCandidateへ変換しました。"
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
        :opportunity_type,
        :opportunity_score,
        :expected_value_yen,
        :confidence,
        :status,
        :business_id,
        metadata: {}
      ])
    end

    def record_decision!(decision_type, decision_source, previous_status:, metadata: {})
      OwnerDecisionLog.record!(
        subject: @opportunity,
        decision_type:,
        decision_source:,
        previous_status:,
        new_status: @opportunity.status,
        metadata:
      )
    end
  end
end
