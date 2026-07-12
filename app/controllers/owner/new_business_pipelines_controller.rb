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

    def create_landing_page
      candidate = ActionCandidate.find(params.expect(:id))
      landing_page = Aicoo::Owner::NewBusinessLandingPageBuilder.new(candidate).call
      redirect_to owner_new_business_pipeline_path(selected_id: candidate.id, anchor: "selected-candidate"),
                  notice: "LPを作成しました: #{landing_page.public_headline}"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to owner_new_business_pipeline_path(selected_id: params[:id], anchor: "selected-candidate"),
                  alert: "LPを作成できません: #{e.record.errors.full_messages.to_sentence}"
    rescue ArgumentError => e
      redirect_to owner_new_business_pipeline_path(selected_id: params[:id], anchor: "selected-candidate"),
                  alert: "LPを作成できません: #{e.message}"
    end

    def publish_landing_page
      landing_page = AicooLabLandingPage.find(params.expect(:id))
      Aicoo::LandingPagePublicationService.publish!(landing_page)
      redirect_to owner_new_business_pipeline_path(selected_id: action_candidate_id_for(landing_page), anchor: "selected-candidate"),
                  notice: "LPを公開しました: /lp/#{landing_page.published_slug}"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to owner_new_business_pipeline_path(anchor: "selected-candidate"),
                  alert: "LPを公開できません: #{e.record.errors.full_messages.to_sentence}"
    end

    def update_landing_page
      landing_page = AicooLabLandingPage.find(params.expect(:id))
      Aicoo::LandingPagePublicationService.update_content!(landing_page, attributes: landing_page_params)
      redirect_to owner_new_business_pipeline_path(selected_id: action_candidate_id_for(landing_page), anchor: "selected-candidate"),
                  notice: "LP内容を保存しました。"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to owner_new_business_pipeline_path(anchor: "selected-candidate"),
                  alert: "LP内容を保存できません: #{e.record.errors.full_messages.to_sentence}"
    end

    private

    def landing_page_params
      params.expect(
        aicoo_lab_landing_page: [
          :headline,
          :subheadline,
          :body,
          :cta_text,
          :seo_title,
          :seo_description,
          :published_slug
        ]
      )
    end

    def action_candidate_id_for(landing_page)
      landing_page.notes.to_s[/ActionCandidate ID: (\d+)/, 1] ||
        ActionCandidate.find_by(business: landing_page.business, department: "new_business")&.id
    end
  end
end
