class AddBusinessToAicooLabExperimentCandidates < ActiveRecord::Migration[8.1]
  def change
    add_reference :aicoo_lab_experiment_candidates, :business, foreign_key: true
  end
end
