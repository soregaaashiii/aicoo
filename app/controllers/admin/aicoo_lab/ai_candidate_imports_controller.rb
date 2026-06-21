module Admin
  module AicooLab
    class AiCandidateImportsController < ApplicationController
      def new
        @prompt = prompt_builder.call
        @response = sample_response
      end

      def create
        result = AicooLabAiCandidateImportService.new(
          prompt: import_params.fetch(:prompt),
          response: import_params.fetch(:response)
        ).call

        redirect_to admin_aicoo_lab_candidates_path,
                    notice: import_notice(result)
      rescue ArgumentError, ActiveRecord::RecordInvalid => e
        @prompt = import_params[:prompt].presence || prompt_builder.call
        @response = import_params[:response]
        flash.now[:alert] = "AI candidate import failed: #{e.message}"
        render :new, status: :unprocessable_content
      end

      private

      def import_params
        params.expect(ai_candidate_import: %i[prompt response])
      end

      def prompt_builder
        AicooLabAiCandidatePromptBuilder.new
      end

      def sample_response
        JSON.pretty_generate(
          candidates: [
            {
              title: "小規模店舗向け問い合わせ整理LP実験",
              description: "問い合わせ対応の負担を減らす訴求で、事前登録CTAへの反応を測る。",
              experiment_type: "lp",
              market_category: "小規模店舗",
              acquisition_channel: "seo",
              expected_90d_profit_yen: 50_000,
              success_probability: 0.25,
              budget_yen: 0,
              estimated_work_minutes: 60,
              assumed_price_yen: 9_800,
              neglect_loss_90d_yen: 0,
              neglect_loss_reason: "放置による明確な損失はまだ見込まない。",
              rationale: "低コストで公開でき、困り度と価格反応を早く測れる。",
              target_user: "問い合わせ対応に時間を取られている小規模店舗オーナー",
              problem_statement: "問い合わせ内容の整理に時間がかかり、本業時間を圧迫している。",
              hypothesis: "問い合わせ整理の訴求に一定のSignup反応があれば、手動MVPで価値検証できる。",
              validation_method: "LPを公開し、PV・CTAクリック・Signupを30日から90日で測定する。",
              expected_learning: "課題訴求、価格、CTAのどこに反応があるか学習する。",
              rejection_condition: "1000PV到達または90日経過時点でCTA率1%未満、Signup0件なら棄却する。"
            }
          ]
        )
      end

      def import_notice(result)
        "Imported #{result.created_candidates.size} AI pasted candidates. Skipped #{result.skipped_titles.size} duplicates."
      end
    end
  end
end
