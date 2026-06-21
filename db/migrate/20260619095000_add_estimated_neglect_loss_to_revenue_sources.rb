class AddEstimatedNeglectLossToRevenueSources < ActiveRecord::Migration[8.0]
  TABLES = %i[
    action_candidates
    aicoo_lab_experiment_candidates
    aicoo_lab_experiments
  ].freeze

  def change
    TABLES.each do |table|
      add_column table, :estimated_neglect_loss_90d_yen, :integer, default: 0, null: false
      add_column table, :neglect_loss_auto_generated, :boolean, default: false, null: false
    end
  end
end
