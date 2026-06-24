module Admin
  class ExploreImportsController < ApplicationController
    before_action :assign_templates

    def new
      assign_form_defaults
    end

    def preview
      assign_form_values
      @preview_result = Aicoo::ExploreImportService.preview(**service_attributes)
      render :new, status: :ok
    end

    def create
      result = Aicoo::ExploreImportService.run!(**service_attributes)
      if result.errors.any?
        assign_form_values
        @preview_result = result
        render :new, status: :unprocessable_entity
      else
        redirect_to admin_explore_path, notice: "Explore Observationを#{result.imported_count}件取り込みました。"
      end
    end

    private

    def assign_form_defaults
      @source_type = "google_trends"
      @import_format = "csv"
      @raw_text = ""
    end

    def assign_templates
      @import_templates = Aicoo::ExploreImportTemplates.all
      @csv_header = Aicoo::ExploreImportTemplates.csv_header
    end

    def assign_form_values
      @source_type = explore_import_params[:source_type].presence || "google_trends"
      @import_format = explore_import_params[:import_format].presence || "csv"
      @raw_text = explore_import_params[:raw_text].to_s
    end

    def service_attributes
      {
        source_type: explore_import_params[:source_type],
        format: explore_import_params[:import_format],
        raw_text: explore_import_params[:raw_text]
      }
    end

    def explore_import_params
      params.fetch(:explore_import, ActionController::Parameters.new).permit(:source_type, :import_format, :raw_text)
    end
  end
end
