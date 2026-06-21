module Admin
  module AicooLab
    class LandingPagesController < ApplicationController
      before_action :set_experiment
      before_action :set_landing_page, only: %i[ edit update preview_ready publish unpublish ]

      def new
        if @experiment.aicoo_lab_landing_page
          redirect_to edit_admin_aicoo_lab_experiment_landing_page_path(@experiment)
          return
        end

        @landing_page = AicooLabLandingPage.build_from_experiment(@experiment)
      end

      def create
        @landing_page = @experiment.build_aicoo_lab_landing_page(landing_page_params)

        if @landing_page.save
          redirect_to admin_aicoo_lab_experiment_path(@experiment), notice: "Landing page was successfully created."
        else
          render :new, status: :unprocessable_content
        end
      end

      def edit
      end

      def update
        if @landing_page.update(landing_page_params)
          redirect_to admin_aicoo_lab_experiment_path(@experiment), notice: "Landing page was successfully updated."
        else
          render :edit, status: :unprocessable_content
        end
      end

      def preview_ready
        @landing_page.mark_preview_ready!
        redirect_to admin_aicoo_lab_experiment_path(@experiment), notice: "Landing page is preview ready."
      end

      def publish
        if @landing_page.publishable?
          @landing_page.publish!
          redirect_to admin_aicoo_lab_experiment_path(@experiment), notice: "LPを無料公開しました。"
        else
          redirect_to admin_aicoo_lab_experiment_path(@experiment), alert: "LP作成済み、かつ承認済みの検証だけ公開できます。"
        end
      end

      def unpublish
        @landing_page.unpublish!
        redirect_to admin_aicoo_lab_experiment_path(@experiment), notice: "LPを非公開にしました。"
      end

      private

      def set_experiment
        @experiment = AicooLabExperiment.find(params.expect(:experiment_id))
      end

      def set_landing_page
        @landing_page = @experiment.aicoo_lab_landing_page
        redirect_to new_admin_aicoo_lab_experiment_landing_page_path(@experiment), alert: "Landing page is not created yet." unless @landing_page
      end

      def landing_page_params
        params.expect(
          aicoo_lab_landing_page: [
            :headline, :subheadline, :body, :cta_text, :assumed_price_yen, :status, :preview_slug, :published_slug,
            :generated_at, :notes
          ]
        )
      end
    end
  end
end
