class BackfillOwnerValueFieldsOnActionCandidates < ActiveRecord::Migration[8.1]
  def up
    ActionCandidate.reset_column_information
    ActionCandidate.find_each do |action_candidate|
      action_candidate.save!(validate: false)
    end
  end

  def down
    # No-op: owner value fields are derived from the current ActionCandidate data.
  end
end
