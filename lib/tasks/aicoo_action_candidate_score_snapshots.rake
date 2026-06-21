namespace :aicoo do
  desc "Snapshot ActionCandidate Judge-adjusted scores. Usage: bin/rails aicoo:snapshot_action_candidate_scores[2026-06-21]"
  task :snapshot_action_candidate_scores, [ :recorded_on ] => :environment do |_task, args|
    recorded_on = args[:recorded_on].present? ? Date.parse(args[:recorded_on]) : Date.current
    result = ActionCandidateScoreSnapshotter.new.snapshot!(date: recorded_on)

    puts "AICOO ActionCandidate score snapshot recorded_on=#{recorded_on}"
    puts "snapshots_created_count=#{result.created_count}"
    puts "rank_up_count=#{result.rank_up_count}"
    puts "rank_down_count=#{result.rank_down_count}"
    puts "no_adjustment_count=#{result.no_adjustment_count}"
  rescue Date::Error => e
    warn "Invalid recorded_on: #{args[:recorded_on]} #{e.message}"
    exit 1
  end
end
