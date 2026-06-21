require "test_helper"

module Admin
  module AicooLab
    class ExperimentCandidatesControllerTest < ActionDispatch::IntegrationTest
      test "should get index" do
        get admin_aicoo_lab_candidates_url
        assert_response :success
        assert_includes response.body, "ここではAIやルールで作られた事業アイデアを確認します"
      end

      test "should get new with template" do
        get new_admin_aicoo_lab_candidate_url(template: "seo")
        assert_response :success
        assert_includes response.body, "ロングテールSEO"
        assert_includes response.body, "検索需要と競合強度"
      end

      test "should create candidate" do
        assert_difference("AicooLabExperimentCandidate.count") do
          post admin_aicoo_lab_candidates_url, params: { aicoo_lab_experiment_candidate: candidate_params }
        end

        assert_redirected_to admin_aicoo_lab_candidate_url(AicooLabExperimentCandidate.last)
      end

      test "should show hypothesis fields" do
        candidate = AicooLabExperimentCandidate.create!(candidate_params)

        get admin_aicoo_lab_candidate_url(candidate)

        assert_response :success
        assert_includes response.body, "対象ユーザー"
        assert_includes response.body, "Small operator"
        assert_includes response.body, "Problem to validate"
        assert_includes response.body, "Hypothesis to test"
        assert_includes response.body, "Learning target"
        assert_includes response.body, "Reject if weak response"
        assert_includes response.body, "放置損失"
        assert_includes response.body, "SEO放置による順位低下リスク"
      end

      test "should approve reject and convert candidate" do
        candidate = AicooLabExperimentCandidate.create!(candidate_params)

        patch approve_admin_aicoo_lab_candidate_url(candidate)
        assert_equal "approved", candidate.reload.status

        patch reject_admin_aicoo_lab_candidate_url(candidate)
        assert_equal "rejected", candidate.reload.status

        assert_difference("AicooLabExperiment.count") do
          post convert_to_experiment_admin_aicoo_lab_candidate_url(candidate)
        end
        assert_equal "converted", candidate.reload.status
        assert_equal candidate.neglect_loss_90d_yen, candidate.converted_experiment.neglect_loss_90d_yen
        assert_equal candidate.neglect_loss_reason, candidate.converted_experiment.neglect_loss_reason
      end

      test "should generate candidates" do
        assert_difference("AicooLabExperimentCandidate.count", 10) do
          assert_difference("AicooLabGenerationRun.count") do
            post generate_admin_aicoo_lab_candidates_url
          end
        end

        assert_redirected_to admin_aicoo_lab_candidates_url
        assert_equal 10, AicooLabExperimentCandidate.where(generation_source: "rule_based").count
        assert_equal 10, AicooLabGenerationRun.last.generated_count
        assert_equal "candidate_generation", AicooLabGenerationRun.last.generation_type
      end

      test "lists candidates by lab priority score" do
        low = AicooLabExperimentCandidate.create!(
          candidate_params.merge(
            title: "Low priority candidate",
            expected_90d_profit_yen: 1_000,
            success_probability: 0.1,
            budget_yen: 500,
            estimated_work_minutes: 120,
            experiment_type: "seo"
          )
        )
        high = AicooLabExperimentCandidate.create!(
          candidate_params.merge(
            title: "High priority candidate",
            expected_90d_profit_yen: 100_000,
            success_probability: 0.5,
            budget_yen: 0,
            estimated_work_minutes: 15,
            experiment_type: "lp"
          )
        )

        get admin_aicoo_lab_candidates_url

        assert_response :success
        assert_operator response.body.index(high.title), :<, response.body.index(low.title)
      end

      test "should convert candidate with landing page and prediction" do
        candidate = AicooLabExperimentCandidate.create!(candidate_params)

        assert_difference("AicooLabExperiment.count") do
          assert_difference("AicooLabLandingPage.count") do
            assert_difference("AicooLabPrediction.count") do
              post convert_to_experiment_with_landing_page_admin_aicoo_lab_candidate_url(candidate)
            end
          end
        end

        experiment = candidate.reload.converted_experiment
        assert_redirected_to admin_aicoo_lab_experiment_url(experiment)
        assert_equal "converted", candidate.status
        assert_equal "preview_ready", experiment.status
        assert_equal "preview_ready", experiment.aicoo_lab_landing_page.status
      end

      test "should bulk convert candidates with landing pages" do
        first_candidate = AicooLabExperimentCandidate.create!(candidate_params.merge(title: "Bulk candidate 1"))
        second_candidate = AicooLabExperimentCandidate.create!(candidate_params.merge(title: "Bulk candidate 2", status: "approved"))

        assert_difference("AicooLabExperiment.count", 2) do
          assert_difference("AicooLabLandingPage.count", 2) do
            assert_difference("AicooLabPrediction.count", 2) do
              post bulk_convert_with_landing_pages_admin_aicoo_lab_candidates_url,
                   params: { candidate_ids: [ first_candidate.id, second_candidate.id ] }
            end
          end
        end

        assert_redirected_to admin_aicoo_lab_experiments_url
        assert_equal "converted", first_candidate.reload.status
        assert_equal "converted", second_candidate.reload.status
      end

      private

      def candidate_params
        {
          title: "Candidate test",
          description: "Candidate description",
          experiment_type: "lp",
          market_category: "smoke test",
          acquisition_channel: "seo",
          expected_90d_profit_yen: 50_000,
          success_probability: 0.4,
          budget_yen: 1_000,
          estimated_work_minutes: 180,
          neglect_loss_90d_yen: 12_000,
          neglect_loss_reason: "SEO放置による順位低下リスク",
          assumed_price_yen: 9_800,
          lp_word_count: 900,
          cta_count: 1,
          rationale: "Good teacher data",
          target_user: "Small operator",
          problem_statement: "Problem to validate",
          hypothesis: "Hypothesis to test",
          validation_method: "LP validation",
          expected_learning: "Learning target",
          rejection_condition: "Reject if weak response",
          status: "proposed"
        }
      end
    end
  end
end
