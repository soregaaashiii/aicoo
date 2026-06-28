module Admin
  module AicooLab
    class PublicLandingPagesController < ApplicationController
      before_action :set_landing_page, only: %i[edit update publish]

      def index
        @status_filter = params[:public_status].presence
        @landing_pages = AicooLabLandingPage
                         .includes(:aicoo_lab_experiment)
                         .where(public_status: visible_statuses)
                         .order(updated_at: :desc)
      end

      def new
        @landing_page = AicooLabLandingPage.new(
          public_status: "draft",
          status: "draft",
          cta_text: "事前登録する"
        )
      end

      def create
        @landing_page = build_landing_page_from_params

        if @landing_page.save
          redirect_to admin_aicoo_lab_edit_public_landing_page_path(@landing_page), notice: "LPをdraftとして作成しました。内容を確認して公開できます。"
        else
          render :new, status: :unprocessable_content
        end
      end

      def edit
      end

      def update
        if @landing_page.update(landing_page_params)
          sync_experiment_from_landing_page!
          redirect_to admin_aicoo_lab_edit_public_landing_page_path(@landing_page), notice: "LPを保存しました。"
        else
          render :edit, status: :unprocessable_content
        end
      end

      def publish
        @landing_page.transaction do
          @landing_page.aicoo_lab_experiment.update!(status: "preview_ready", approval_status: "approved")
          @landing_page.update!(status: "preview_ready")
          @landing_page.publish!
        end
        AicooAnalytics::SiteAutolinker.new(base_url: request.base_url).link!(@landing_page)
        redirect_to admin_aicoo_lab_edit_public_landing_page_path(@landing_page), notice: "LPを公開しました。/ と /lp と sitemap.xml に自動反映されます。"
      rescue ActiveRecord::RecordInvalid => error
        redirect_to admin_aicoo_lab_edit_public_landing_page_path(@landing_page), alert: "LPを公開できませんでした: #{error.record.errors.full_messages.to_sentence}"
      end

      private

      def set_landing_page
        @landing_page = AicooLabLandingPage.find(params.expect(:id))
      end

      def visible_statuses
        return @status_filter if @status_filter.in?(AicooLabLandingPage::PUBLIC_STATUSES)

        AicooLabLandingPage::PUBLIC_STATUSES
      end

      def build_landing_page_from_params
        experiment = AicooLabExperiment.new(experiment_attributes)
        experiment.build_aicoo_lab_landing_page(
          landing_page_params.merge(status: "draft", public_status: "draft")
        )
      end

      def experiment_attributes
        {
          title: landing_page_params[:headline].presence || "公開LP",
          description: landing_page_params[:subheadline],
          notes: landing_page_params[:body],
          experiment_type: "lp",
          acquisition_channel: "seo",
          status: "draft",
          approval_status: "not_required",
          assumed_price_yen: landing_page_params[:assumed_price_yen]
        }
      end

      def sync_experiment_from_landing_page!
        @landing_page.aicoo_lab_experiment.update!(
          title: @landing_page.headline.presence || @landing_page.aicoo_lab_experiment.title,
          description: @landing_page.subheadline,
          notes: @landing_page.body,
          assumed_price_yen: @landing_page.assumed_price_yen
        )
      end

      def landing_page_params
        params.expect(
          aicoo_lab_landing_page: [
            :headline, :subheadline, :body, :cta_text, :assumed_price_yen, :published_slug,
            :seo_title, :seo_description, :og_title, :og_description, :og_image_url, :canonical_url, :notes
          ]
        )
      end
    end
  end
end
