module Owner
  class NewBusinessPipelinesController < ApplicationController
    def show
      @board = Aicoo::Owner::NewBusinessPipelineBoard.new(selected_id: params[:selected_id]).call
    end

    def approve_candidate
      candidate = ActionCandidate.find(params.expect(:id))
      result = Aicoo::ApprovalService.approve(candidate, operator: "owner", source: "owner_new_business_pipeline")
      business = result.redirect_record if result.redirect_record.is_a?(Business)
      business ||= Business.find_by(id: candidate.reload.metadata.to_h.dig("business_promotion", "business_id"))

      redirect_to owner_new_business_pipeline_path(selected_id: candidate.id, anchor: "selected-candidate"),
                  notice: business ? "Businessを作成しました: #{business.name}" : result.message
    rescue ActiveRecord::RecordInvalid => e
      redirect_to owner_new_business_pipeline_path(selected_id: params[:id], anchor: "selected-candidate"),
                  alert: "Business化できませんでした: #{e.record.errors.full_messages.to_sentence}"
    end

    def reject_candidate
      candidate = ActionCandidate.find(params.expect(:id))
      result = Aicoo::ApprovalService.reject(candidate, operator: "owner", source: "owner_new_business_pipeline")
      redirect_to owner_new_business_pipeline_path(selected_id: candidate.id, anchor: "selected-candidate"),
                  notice: result.message
    end
  end
end
