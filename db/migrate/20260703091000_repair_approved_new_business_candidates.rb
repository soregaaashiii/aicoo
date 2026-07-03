class RepairApprovedNewBusinessCandidates < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:action_candidates) && table_exists?(:businesses)

    ActionCandidate.reset_column_information
    Business.reset_column_information

    result = Aicoo::ApprovedNewBusinessCandidateRepairer.call(
      source: "migration_repair_approved_new_business_candidates"
    )
    say "approved_new_business_candidates checked=#{result.checked_count} repaired=#{result.repaired_count} skipped=#{result.skipped_count} failed=#{result.failed_count}"
  end

  def down
    # Non destructive data repair. Do not remove created Business records on rollback.
  end
end
