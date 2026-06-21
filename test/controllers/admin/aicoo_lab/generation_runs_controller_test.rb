require "test_helper"

module Admin
  module AicooLab
    class GenerationRunsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @generation_run = AicooLabGenerationRun.create!(
          generation_type: "candidate_generation",
          prompt: "Rule based prompt",
          response: "- Generated candidate",
          status: "succeeded",
          generated_count: 1,
          started_at: 1.minute.ago,
          finished_at: Time.current,
          metadata: { "generator" => "test" }
        )
      end

      test "should get index" do
        get admin_aicoo_lab_generation_runs_url

        assert_response :success
        assert_includes response.body, "アイデア生成履歴"
        assert_includes response.body, "candidate_generation"
        assert_includes response.body, "succeeded"
      end

      test "should show generation run" do
        get admin_aicoo_lab_generation_run_url(@generation_run)

        assert_response :success
        assert_includes response.body, "Rule based prompt"
        assert_includes response.body, "Generated candidate"
        assert_includes response.body, "生成件数"
      end
    end
  end
end
