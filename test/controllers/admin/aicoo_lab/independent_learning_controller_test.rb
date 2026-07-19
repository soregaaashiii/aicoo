require "test_helper"

module Admin
  module AicooLab
    class IndependentLearningControllerTest < ActionDispatch::IntegrationTest
      test "shows independent learning without adding it to Today" do
        get admin_aicoo_lab_independent_learning_url

        assert_response :success
        assert_includes response.body, "Independent Learning"
        assert_includes response.body, "エリア・ジャンル別の独立学習"
        assert_includes response.body, "ActionCandidate候補化"
      end
    end
  end
end
