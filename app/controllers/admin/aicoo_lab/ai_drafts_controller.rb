module Admin
  module AicooLab
    class AiDraftsController < ApplicationController
      before_action :set_ai_draft, only: %i[ show approve reject import_candidates ]

      def index
        @ai_drafts = AicooLabAiDraft.includes(:generation_run).recent
      end

      def new
        @prompt = prompt_builder.call
        @raw_response = sample_response
        @title = "AI candidate draft #{Time.current.strftime('%Y-%m-%d %H:%M')}"
      end

      def create
        result = AicooLabAiDraftCreator.new(
          title: draft_params.fetch(:title),
          prompt: draft_params.fetch(:prompt),
          raw_response: draft_params.fetch(:raw_response)
        ).call

        redirect_to admin_aicoo_lab_ai_draft_path(result.ai_draft), notice: "AI draft was created."
      rescue ArgumentError, ActiveRecord::RecordInvalid => e
        @title = draft_params[:title]
        @prompt = draft_params[:prompt].presence || prompt_builder.call
        @raw_response = draft_params[:raw_response]
        flash.now[:alert] = "AI draft creation failed: #{e.message}"
        render :new, status: :unprocessable_content
      end

      def show
      end

      def approve
        @ai_draft.approve!
        redirect_to admin_aicoo_lab_ai_draft_path(@ai_draft), notice: "AI draft was approved."
      end

      def reject
        @ai_draft.reject!
        redirect_to admin_aicoo_lab_ai_draft_path(@ai_draft), notice: "AI draft was rejected."
      end

      def import_candidates
        result = AicooLabAiDraftImporter.new(@ai_draft).call
        redirect_to admin_aicoo_lab_candidates_path,
                    notice: "Imported #{result.created_candidates.size} candidates. Skipped #{result.skipped_titles.size} duplicates."
      rescue ArgumentError, ActiveRecord::RecordInvalid => e
        redirect_to admin_aicoo_lab_ai_draft_path(@ai_draft), alert: "AI draft import failed: #{e.message}"
      end

      private

      def set_ai_draft
        @ai_draft = AicooLabAiDraft.find(params.expect(:id))
      end

      def draft_params
        params.expect(ai_draft: %i[title prompt raw_response])
      end

      def prompt_builder
        AicooLabAiCandidatePromptBuilder.new
      end

      def sample_response
        JSON.pretty_generate(
          candidates: [
            {
              title: "AI下書きサンプルLP実験",
              description: "AI出力を下書きとしてレビューし、承認後に候補化するためのサンプル。",
              experiment_type: "lp",
              market_category: "サンプル市場",
              acquisition_channel: "seo",
              expected_90d_profit_yen: 50_000,
              success_probability: 0.25,
              budget_yen: 0,
              estimated_work_minutes: 60,
              assumed_price_yen: 9_800,
              neglect_loss_90d_yen: 0,
              neglect_loss_reason: "放置による明確な損失はまだ見込まない。",
              rationale: "低コストでLP検証でき、AI出力レビューの流れを確認しやすい。",
              target_user: "明確な業務課題を持つ小規模事業者",
              problem_statement: "課題はあるが、開発前に需要反応を確認できていない。",
              hypothesis: "LPに一定のCTA反応があれば、次の手動MVPへ進む価値がある。",
              validation_method: "LPを公開し、PV・CTAクリック・Signupを30日から90日で測定する。",
              expected_learning: "訴求、価格、獲得チャネルの初速を学習する。",
              rejection_condition: "1000PV到達または90日経過時点でCTA率1%未満、Signup0件なら棄却する。"
            }
          ]
        )
      end
    end
  end
end
