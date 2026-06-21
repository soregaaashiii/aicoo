require "test_helper"

module Admin
  module AicooLab
    class AiDraftsControllerTest < ActionDispatch::IntegrationTest
      test "should create ai draft" do
        assert_difference("AicooLabAiDraft.count") do
          assert_difference("AicooLabGenerationRun.count") do
            post admin_aicoo_lab_ai_drafts_url, params: draft_params
          end
        end

        draft = AicooLabAiDraft.last
        assert_redirected_to admin_aicoo_lab_ai_draft_url(draft)
        assert_equal "draft", draft.status
        assert_equal 2, draft.candidate_count
        assert_equal "candidate_generation", draft.generation_run.generation_type
      end

      test "should get index and show" do
        draft = create_ai_draft!

        get admin_aicoo_lab_ai_drafts_url
        assert_response :success
        assert_includes response.body, draft.title
        assert_includes response.body, "候補数"
        assert_includes response.body, "ここではAIが出したJSON候補を確認し"

        get admin_aicoo_lab_ai_draft_url(draft)
        assert_response :success
        assert_includes response.body, "AI出力"
        assert_includes response.body, "解析済みJSON"
        assert_includes response.body, "候補数"
        assert_includes response.body, "Prompt for AI draft"
      end

      test "should approve and reject ai draft" do
        draft = create_ai_draft!

        patch approve_admin_aicoo_lab_ai_draft_url(draft)
        assert_redirected_to admin_aicoo_lab_ai_draft_url(draft)
        assert_equal "approved", draft.reload.status
        assert_not_nil draft.approved_at

        patch reject_admin_aicoo_lab_ai_draft_url(draft)
        assert_equal "rejected", draft.reload.status
      end

      test "should import candidates from approved draft" do
        draft = create_ai_draft!
        draft.approve!

        assert_difference("AicooLabExperimentCandidate.count", 2) do
          post import_candidates_admin_aicoo_lab_ai_draft_url(draft)
        end

        assert_redirected_to admin_aicoo_lab_candidates_url
        assert_equal "imported", draft.reload.status
        assert_not_nil draft.imported_at
        assert_equal 2, AicooLabExperimentCandidate.where(generation_source: "ai_paste").count
        assert_equal 2, draft.generation_run.reload.generated_count
      end

      test "should not import candidates from unapproved draft" do
        draft = create_ai_draft!

        assert_no_difference("AicooLabExperimentCandidate.count") do
          post import_candidates_admin_aicoo_lab_ai_draft_url(draft)
        end

        assert_redirected_to admin_aicoo_lab_ai_draft_url(draft)
        assert_equal "draft", draft.reload.status
      end

      private

      def create_ai_draft!
        AicooLabAiDraftCreator.new(
          title: "AI draft test",
          prompt: "Prompt for AI draft",
          raw_response: ai_response_json
        ).call.ai_draft
      end

      def draft_params
        {
          ai_draft: {
            title: "AI draft test",
            prompt: "Prompt for AI draft",
            raw_response: ai_response_json
          }
        }
      end

      def ai_response_json
        JSON.generate(candidates: [
          candidate_attributes(title: "Draft candidate 1"),
          candidate_attributes(title: "Draft candidate 2", experiment_type: "seo", acquisition_channel: "seo")
        ])
      end

      def candidate_attributes(title:, experiment_type: "lp", acquisition_channel: "sns")
        {
          title:,
          description: "#{title} description",
          experiment_type:,
          market_category: "AI draft market",
          acquisition_channel:,
          expected_90d_profit_yen: 50_000,
          success_probability: 0.25,
          budget_yen: 0,
          estimated_work_minutes: 60,
          assumed_price_yen: 9_800,
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
