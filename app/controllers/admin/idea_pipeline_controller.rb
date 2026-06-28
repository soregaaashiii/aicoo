module Admin
  class IdeaPipelineController < ApplicationController
    before_action :set_item, only: %i[show score run_serp generate_lp publish_lp evaluate_learning build_mvp_spec run_pipeline]

    def index
      @items = IdeaPipelineItem.includes(:aicoo_lab_landing_page).by_priority
      @stage_counts = IdeaPipelineItem.group(:current_stage).count
      @latest_items = @items.limit(50)
    end

    def show
    end

    def generate
      result = Aicoo::IdeaPipeline::IdeaGenerator.call(count: params[:count].presence || 3)
      redirect_to admin_idea_pipeline_index_path, notice: "Ideaを#{result.created_count}件生成しました。"
    end

    def score
      Aicoo::IdeaPipeline::IdeaScorer.new(@item).call
      redirect_to admin_idea_pipeline_path(@item), notice: "期待値評価を更新しました。"
    end

    def run_serp
      Aicoo::IdeaPipeline::SerpEvaluator.new(@item).call
      redirect_to admin_idea_pipeline_path(@item), notice: "SERP判定を実行しました。"
    end

    def generate_lp
      landing_page = Aicoo::IdeaPipeline::LandingPageBuilder.new(@item).call
      redirect_to admin_idea_pipeline_path(@item), notice: "draft LPを生成しました: #{landing_page.headline}"
    rescue ArgumentError => e
      redirect_to admin_idea_pipeline_path(@item), alert: e.message
    end

    def publish_lp
      Aicoo::IdeaPipeline::Publisher.new(@item).call
      redirect_to admin_idea_pipeline_path(@item), notice: "公開LPをpublishedにしました。/ と /lp と sitemap.xml に反映されます。"
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to admin_idea_pipeline_path(@item), alert: "LPを公開できませんでした: #{e.message}"
    end

    def evaluate_learning
      Aicoo::IdeaPipeline::LearningEvaluator.new(@item).call
      redirect_to admin_idea_pipeline_path(@item), notice: "反応計測を評価しました。"
    end

    def build_mvp_spec
      Aicoo::IdeaPipeline::MvpSpecBuilder.new(@item).call
      redirect_to admin_idea_pipeline_path(@item), notice: "MVP判断とCodex向け仕様書を生成しました。"
    end

    def run_pipeline
      Aicoo::IdeaPipeline::PipelineRunner.new(@item).run_until_blocked!
      redirect_to admin_idea_pipeline_path(@item), notice: "Idea Pipelineを進めました。"
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to admin_idea_pipeline_path(@item), alert: "Pipelineを進められませんでした: #{e.message}"
    end

    private

    def set_item
      @item = IdeaPipelineItem.find(params.expect(:id))
    end
  end
end
