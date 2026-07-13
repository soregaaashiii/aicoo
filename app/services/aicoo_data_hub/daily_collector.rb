module AicooDataHub
  class DailyCollector
    def initialize(snapshot_collector: SnapshotCollector.new)
      @snapshot_collector = snapshot_collector
    end

    def call
      run = AicooDataHubCollectionRun.create!(status: "running", started_at: Time.current)

      snapshot_count = collect_snapshot_count
      run.update!(
        status: "success",
        finished_at: Time.current,
        snapshot_count:
      )
      run
    rescue StandardError
      run&.update!(
        status: "failed",
        finished_at: Time.current,
        snapshot_count: run.snapshot_count.to_i
      )
      raise
    end

    private

    attr_reader :snapshot_collector

    def collect_snapshot_count
      snapshot_collector.collect_all.count
    end
  end
end
