require "test_helper"

module Admin
  module AicooLab
    class PredictionsControllerTest < ActionDispatch::IntegrationTest
      test "should create prediction" do
        experiment = AicooLabExperiment.create!(title: "Prediction test", experiment_type: "lp", acquisition_channel: "seo")

        assert_difference("AicooLabPrediction.count") do
          post admin_aicoo_lab_experiment_predictions_url(experiment), params: {
            aicoo_lab_prediction: {
              prediction_type: "profit",
              target_days: 90,
              predicted_value: 10_000,
              predicted_value_unit: "yen",
              confidence: 0.7
            }
          }
        end

        assert_redirected_to admin_aicoo_lab_experiment_url(experiment)
        assert_equal "human", AicooLabPrediction.last.prediction_source
      end
    end
  end
end
