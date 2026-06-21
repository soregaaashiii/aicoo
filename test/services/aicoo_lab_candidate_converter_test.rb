require "test_helper"

class AicooLabCandidateConverterTest < ActiveSupport::TestCase
  test "creates experiment landing page and prediction from candidate" do
    candidate = create_candidate

    assert_difference("AicooLabExperiment.count") do
      assert_difference("AicooLabLandingPage.count") do
        assert_difference("AicooLabPrediction.count") do
          AicooLabCandidateConverter.new([ candidate ]).call
        end
      end
    end

    experiment = candidate.reload.converted_experiment
    landing_page = experiment.aicoo_lab_landing_page
    prediction = experiment.aicoo_lab_predictions.first

    assert_equal "converted", candidate.status
    assert_equal "preview_ready", experiment.status
    assert_equal "preview_ready", landing_page.status
    assert_equal "candidate_conversion", landing_page.generation_source
    assert_equal "profit", prediction.prediction_type
    assert_equal 90, prediction.target_days
    assert_equal candidate.expected_90d_profit_yen.to_d, prediction.predicted_value
    assert_equal "yen", prediction.predicted_value_unit
    assert_equal candidate.success_probability.to_d, prediction.confidence
    assert_equal "lab", prediction.prediction_source
  end

  test "does not duplicate converted candidate" do
    candidate = create_candidate
    AicooLabCandidateConverter.new([ candidate ]).call

    assert_no_difference("AicooLabExperiment.count") do
      assert_no_difference("AicooLabLandingPage.count") do
        assert_no_difference("AicooLabPrediction.count") do
          AicooLabCandidateConverter.new([ candidate.reload ]).call
        end
      end
    end
  end

  private

  def create_candidate(title: "Converter candidate")
    AicooLabExperimentCandidate.create!(
      title:,
      description: "Converter candidate description",
      experiment_type: "lp",
      market_category: "converter market",
      acquisition_channel: "seo",
      expected_90d_profit_yen: 50_000,
      success_probability: 0.4,
      budget_yen: 0,
      estimated_work_minutes: 60,
      assumed_price_yen: 9_800,
      lp_word_count: 900,
      cta_count: 1,
      rationale: "Converter rationale",
      status: "proposed"
    )
  end
end
