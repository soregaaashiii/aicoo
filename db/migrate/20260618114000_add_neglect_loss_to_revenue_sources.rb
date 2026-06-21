class AddNeglectLossToRevenueSources < ActiveRecord::Migration[8.0]
  def change
    add_column :action_candidates, :neglect_loss_90d_yen, :integer, default: 0, null: false
    add_column :action_candidates, :neglect_loss_reason, :text

    add_column :aicoo_lab_experiment_candidates, :neglect_loss_90d_yen, :integer, default: 0, null: false
    add_column :aicoo_lab_experiment_candidates, :neglect_loss_reason, :text

    add_column :aicoo_lab_experiments, :neglect_loss_90d_yen, :integer, default: 0, null: false
    add_column :aicoo_lab_experiments, :neglect_loss_reason, :text
  end
end
