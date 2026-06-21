require "test_helper"

module Admin
  module AicooLab
    class AiCandidateImportsControllerTest < ActionDispatch::IntegrationTest
      test "should get new with prompt and json field" do
        get new_admin_aicoo_lab_ai_candidate_import_url

        assert_response :success
        assert_includes response.body, "AIに渡すプロンプト"
        assert_includes response.body, "JSON貼り付け"
        assert_includes response.body, "monthly_budget_yen"
        assert_includes response.body, "target_user"
        assert_includes response.body, "rejection_condition"
      end

      test "should create candidates from pasted json and generation run" do
        assert_difference("AicooLabExperimentCandidate.count", 2) do
          assert_difference("AicooLabGenerationRun.count") do
            post admin_aicoo_lab_ai_candidate_imports_url, params: import_params
          end
        end

        assert_redirected_to admin_aicoo_lab_candidates_url
        assert_equal 2, AicooLabExperimentCandidate.where(generation_source: "ai_paste").count
        assert_equal "succeeded", AicooLabGenerationRun.last.status
        assert_equal 2, AicooLabGenerationRun.last.generated_count
        assert_includes AicooLabGenerationRun.last.response, "AI pasted candidate 1"
        assert_equal 7_000, AicooLabExperimentCandidate.find_by!(title: "AI pasted candidate 1").neglect_loss_90d_yen
      end

      test "should skip duplicate titles" do
        AicooLabExperimentCandidate.create!(
          candidate_attributes(title: "AI pasted candidate 1").merge(generation_source: "manual")
        )

        assert_difference("AicooLabExperimentCandidate.count", 1) do
          post admin_aicoo_lab_ai_candidate_imports_url, params: import_params
        end

        assert_redirected_to admin_aicoo_lab_candidates_url
        assert_equal 1, AicooLabGenerationRun.last.generated_count
        assert_equal [ "AI pasted candidate 1" ], AicooLabGenerationRun.last.metadata.fetch("skipped_duplicate_titles")
      end

      private

      def import_params
        {
          ai_candidate_import: {
            prompt: "Prompt for AI candidates",
            response: JSON.generate(candidates: [
              candidate_attributes(title: "AI pasted candidate 1"),
              candidate_attributes(title: "AI pasted candidate 2", experiment_type: "seo", acquisition_channel: "seo")
            ])
          }
        }
      end

      def candidate_attributes(title:, experiment_type: "lp", acquisition_channel: "sns")
        {
          title:,
          description: "#{title} description",
          experiment_type:,
          market_category: "AI paste market",
          acquisition_channel:,
          expected_90d_profit_yen: 50_000,
          success_probability: 0.25,
          budget_yen: 0,
          estimated_work_minutes: 60,
          assumed_price_yen: 9_800,
          neglect_loss_90d_yen: 7_000,
          neglect_loss_reason: "#{title} neglect loss",
          rationale: "#{title} rationale",
          target_user: "#{title} target user",
          problem_statement: "#{title} problem",
          hypothesis: "#{title} hypothesis",
          validation_method: "#{title} validation",
          expected_learning: "#{title} learning",
          rejection_condition: "#{title} rejection"
        }
      end
    end
  end
end
