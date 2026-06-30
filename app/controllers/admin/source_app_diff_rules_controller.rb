module Admin
  class SourceAppDiffRulesController < ApplicationController
    def index
      @rules = SourceAppDiffRule.includes(source_app_connection: :business).order(:priority, :id)
    end

    def edit
      @rule = SourceAppDiffRule.find(params[:id])
    end

    def update
      @rule = SourceAppDiffRule.find(params[:id])
      if @rule.update(rule_params)
        redirect_to admin_source_app_diff_rules_path, notice: "Diff Ruleを保存しました"
      else
        flash.now[:alert] = @rule.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def rule_params
      permitted = params.require(:source_app_diff_rule).permit(
        :name,
        :watched_table,
        :resource_type,
        :activity_type,
        :title_template,
        :estimated_work_seconds,
        :enabled,
        :priority,
        watched_fields: [],
        metadata_fields: []
      )
      %i[watched_fields metadata_fields].each do |key|
        permitted[key] = parse_list(params[:source_app_diff_rule][key]) if params[:source_app_diff_rule].key?(key)
      end
      permitted
    end

    def parse_list(value)
      Array(value).flat_map { |item| item.to_s.split(",") }.map(&:strip).reject(&:blank?)
    end
  end
end
