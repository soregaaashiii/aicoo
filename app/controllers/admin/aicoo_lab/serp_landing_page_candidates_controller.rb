module Admin
  module AicooLab
    class SerpLandingPageCandidatesController < ApplicationController
      before_action :set_candidate, only: :create_landing_page

      def index
        @businesses = Business.real_businesses.order(:name)
        @candidates = SerpLandingPageCandidate
                      .includes(:serp_analysis, :aicoo_lab_landing_page)
                      .by_expected_value
      end

      def create
        result = Aicoo::SerpLandingPageCandidateGenerator.new(
          keyword: serp_params[:keyword],
          raw_text: raw_text,
          business: selected_business,
          location: serp_params[:location],
          device: serp_params[:device]
        ).call

        redirect_to admin_aicoo_lab_serp_landing_page_candidates_path,
                    notice: "SERP調査を保存し、LP候補を#{result.candidates.size}件生成しました。"
      rescue ActiveRecord::RecordInvalid => error
        redirect_to admin_aicoo_lab_serp_landing_page_candidates_path,
                    alert: "LP候補を生成できませんでした: #{error.record.errors.full_messages.to_sentence}"
      rescue ArgumentError => error
        redirect_to admin_aicoo_lab_serp_landing_page_candidates_path,
                    alert: "LP候補を生成できませんでした: #{error.message}"
      end

      def create_landing_page
        result = Aicoo::ApprovalService.approve(@candidate, operator: "owner", source: "serp_landing_page_candidates")
        landing_page = result.redirect_record
        redirect_to admin_aicoo_lab_edit_public_landing_page_path(landing_page),
                    notice: result.message
      rescue ActiveRecord::RecordInvalid => error
        redirect_to admin_aicoo_lab_serp_landing_page_candidates_path,
                    alert: "LPを作成できませんでした: #{error.record.errors.full_messages.to_sentence}"
      end

      private

      def set_candidate
        @candidate = SerpLandingPageCandidate.find(params.expect(:id))
      end

      def serp_params
        params.expect(serp_research: [ :business_id, :keyword, :location, :device, :raw_text, :file ])
      end

      def selected_business
        Business.real_businesses.find_by(id: serp_params[:business_id].presence)
      end

      def raw_text
        upload = serp_params[:file]
        upload.present? ? upload.read.force_encoding("UTF-8").scrub : serp_params[:raw_text]
      end
    end
  end
end
