module Admin
  class AicooInsightsController < ApplicationController
    def index
      @summary = AicooInsight::Summary.new
      @insights = @summary.recent_actions
    end

    def generate
      result = AicooInsight::Generator.generate_all!

      redirect_to admin_aicoo_insights_path,
                  notice: "改善案を#{result.created_count}件生成しました。スキップ: #{result.skipped_count}件"
    end
  end
end
