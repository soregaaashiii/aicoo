class BackfillGenerationSourceForExistingAiActions < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE action_candidates
      SET generation_source = 'ai_business'
      WHERE generation_source = 'manual'
        AND EXISTS (
          SELECT 1
          FROM ai_evaluation_runs
          WHERE ai_evaluation_runs.business_id = action_candidates.business_id
            AND ai_evaluation_runs.created_action_count > 0
            AND action_candidates.created_at BETWEEN ai_evaluation_runs.created_at - INTERVAL '1 minute'
                                            AND ai_evaluation_runs.created_at + INTERVAL '1 minute'
        )
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE action_candidates
      SET generation_source = 'manual'
      WHERE generation_source = 'ai_business'
        AND EXISTS (
          SELECT 1
          FROM ai_evaluation_runs
          WHERE ai_evaluation_runs.business_id = action_candidates.business_id
            AND ai_evaluation_runs.created_action_count > 0
            AND action_candidates.created_at BETWEEN ai_evaluation_runs.created_at - INTERVAL '1 minute'
                                            AND ai_evaluation_runs.created_at + INTERVAL '1 minute'
        )
    SQL
  end
end
