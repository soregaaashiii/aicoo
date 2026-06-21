module Admin
  module AicooLab
    class PredictionsController < ApplicationController
      def create
        experiment = AicooLabExperiment.find(params.expect(:experiment_id))
        prediction = experiment.aicoo_lab_predictions.new(prediction_params)
        prediction.prediction_source = "human"

        if prediction.save
          redirect_to admin_aicoo_lab_experiment_path(experiment), notice: "Prediction was added."
        else
          redirect_to admin_aicoo_lab_experiment_path(experiment), alert: prediction.errors.full_messages.to_sentence
        end
      end

      private

      def prediction_params
        params.expect(
          aicoo_lab_prediction: [
            :prediction_type, :target_days, :predicted_value, :predicted_value_unit, :confidence, :rationale, :predicted_at
          ]
        )
      end
    end
  end
end
