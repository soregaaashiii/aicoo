module Admin
  module AicooLab
    class ResultsController < ApplicationController
      def create
        experiment = AicooLabExperiment.find(params.expect(:experiment_id))
        result = experiment.aicoo_lab_results.new(result_params)

        if result.save
          update_scored_at!(experiment, result.target_days)
          redirect_to admin_aicoo_lab_experiment_path(experiment), notice: "Result was added."
        else
          redirect_to admin_aicoo_lab_experiment_path(experiment), alert: result.errors.full_messages.to_sentence
        end
      end

      private

      def result_params
        params.expect(
          aicoo_lab_result: [
            :result_type, :target_days, :actual_value, :actual_value_unit, :measured_at, :sample_size
          ]
        )
      end

      def update_scored_at!(experiment, target_days)
        column = "scored_#{target_days}d_at"
        return unless experiment.has_attribute?(column)

        experiment.update!(column => Time.current)
      end
    end
  end
end
