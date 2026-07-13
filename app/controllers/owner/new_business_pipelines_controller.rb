module Owner
  class NewBusinessPipelinesController < ApplicationController
    def show
      @board = Aicoo::Owner::NewBusinessPipelineBoard.new(selected_id: params[:selected_id], tab: params[:tab]).call
    end

    def approve_candidate
      candidate = ActionCandidate.find(params.expect(:id))
      quality = refresh_business_idea_quality!(candidate)
      unless quality.auto_publishable
        redirect_to owner_new_business_pipeline_path(selected_id: candidate.id, anchor: "selected-candidate"),
                    alert: "Business化前に候補を編集してください: #{quality.reasons.join(' / ')}"
        return
      end

      result = Aicoo::Serp::AutoNewBusinessPublisher.call(
        candidates: [ candidate ],
        source: "owner_new_business_pipeline"
      )
      business = Business.find_by(id: candidate.reload.metadata.to_h.dig("auto_new_business_publication", "business_id"))

      redirect_to owner_new_business_pipeline_path(selected_id: candidate.id, anchor: "selected-candidate"),
                  notice: business ? "Businessを作成しました: #{business.name}" : "Business化を実行しました。作成 #{result.business_created_count}件 / 既存紐付け #{result.business_linked_count}件"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to owner_new_business_pipeline_path(selected_id: params[:id], anchor: "selected-candidate"),
                  alert: "Business化できませんでした: #{e.record.errors.full_messages.to_sentence}"
    end

    def update_candidate
      candidate = ActionCandidate.find(params.expect(:id))
      metadata = candidate.metadata.to_h.merge(normalized_candidate_metadata(candidate_params.to_h))
      quality = quality_for(candidate, metadata)
      candidate.update!(
        title: metadata["business_name"].presence || candidate.title,
        description: business_idea_description(metadata).presence || candidate.description,
        metadata: metadata.merge(
          "business_idea_quality" => quality.to_h,
          "requires_human_edit" => !quality.auto_publishable,
          "manual_approval_required" => true,
          "auto_business_publish_required" => quality.auto_publishable,
          "business_flow" => quality.auto_publishable ? "manual_edit_ready_for_business" : "serp_manual_edit_required"
        )
      )

      redirect_to owner_new_business_pipeline_path(selected_id: candidate.id, anchor: "selected-candidate"),
                  notice: quality.auto_publishable ? "候補を保存しました。Business作成できます。" : "候補を保存しました。まだ編集が必要です。"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to owner_new_business_pipeline_path(selected_id: params[:id], anchor: "selected-candidate"),
                  alert: "候補を保存できません: #{e.record.errors.full_messages.to_sentence}"
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

    def candidate_params
      params.expect(
        action_candidate: [
          :business_name,
          :target_customer,
          :problem,
          :offering,
          :value_proposition,
          :revenue_model,
          :validation_method,
          :market,
          :market_category,
          :region,
          :launch_asset_type
        ]
      )
    end

    def normalized_candidate_metadata(attributes)
      attributes.compact_blank.merge(
        "customer" => attributes["target_customer"].presence,
        "provided_service" => attributes["offering"].presence,
        "solution" => attributes["offering"].presence,
        "monetization" => attributes["revenue_model"].presence,
        "validation_plan" => attributes["validation_method"].presence,
        "validation_step" => attributes["validation_method"].presence,
        "product_type" => attributes["launch_asset_type"].presence,
        "lp_or_saas" => attributes["launch_asset_type"].presence
      ).compact_blank
    end

    def refresh_business_idea_quality!(candidate)
      metadata = candidate.metadata.to_h
      quality = quality_for(candidate, metadata)
      candidate.update!(
        metadata: metadata.merge(
          "business_idea_quality" => quality.to_h,
          "requires_human_edit" => !quality.auto_publishable,
          "manual_approval_required" => metadata["manual_approval_required"] || !quality.auto_publishable,
          "auto_business_publish_required" => quality.auto_publishable
        )
      )
      quality
    end

    def quality_for(candidate, metadata)
      Aicoo::Serp::BusinessIdeaQualityJudge.call(
        attributes: {
          "business_name" => metadata["business_name"].presence || candidate.title,
          "target_customer" => metadata["target_customer"].presence || metadata["customer"].presence,
          "problem" => metadata["problem"],
          "offering" => metadata["offering"].presence || metadata["solution"].presence || metadata["provided_service"],
          "revenue_model" => metadata["revenue_model"].presence || metadata["monetization"],
          "validation_method" => metadata["validation_method"].presence || metadata["validation_plan"].presence || metadata["validation_step"],
          "product_type" => metadata["product_type"].presence || metadata["launch_asset_type"].presence || metadata["lp_or_saas"]
        },
        source_query: metadata["source_query"]
      )
    end

    def business_idea_description(metadata)
      return if metadata["target_customer"].blank? || metadata["problem"].blank? || metadata["offering"].blank?

      "#{metadata['target_customer']}向けに、#{metadata['problem']}を#{metadata['offering']}で解決する新規事業候補です。"
    end

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
