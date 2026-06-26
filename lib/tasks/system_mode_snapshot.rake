namespace :aicoo do
  desc "Generate a System Mode Snapshot for lightweight dashboard rendering"
  task snapshot_system_mode: :environment do
    snapshot = Aicoo::SystemModeSnapshotBuilder.new.call
    puts "SystemModeSnapshot ##{snapshot.id} captured_at=#{snapshot.captured_at.iso8601} health_score=#{snapshot.health_score}"
  end
end
