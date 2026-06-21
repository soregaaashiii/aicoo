require "test_helper"

module Admin
  module AicooLab
    class ResultsControllerTest < ActionDispatch::IntegrationTest
      test "should create result" do
        experiment = AicooLabExperiment.create!(title: "Result test", experiment_type: "lp", acquisition_channel: "seo")

        assert_difference("AicooLabResult.count") do
          post admin_aicoo_lab_experiment_results_url(experiment), params: {
            aicoo_lab_result: {
              result_type: "profit",
              target_days: 90,
              actual_value: 8_000,
              actual_value_unit: "yen",
              sample_size: 100
            }
          }
        end

        assert_redirected_to admin_aicoo_lab_experiment_url(experiment)
        assert_not_nil experiment.reload.scored_90d_at
      end
    end
  end
end
