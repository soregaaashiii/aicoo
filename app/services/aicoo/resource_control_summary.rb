module Aicoo
  class ResourceControlSummary
    Result = Data.define(
      :attention_rows,
      :today_businesses,
      :watch_businesses,
      :paused_businesses,
      :archived_count,
      :active_count,
      :auto_snooze_candidates
    )

    def call
      attention_rows = Aicoo::AttentionScore.ranking

      Result.new(
        attention_rows:,
        today_businesses: attention_rows.select { |row| row.score >= 20 && row.business.resource_status != "archived" },
        watch_businesses: Business.real_businesses.resource_watch.order(:name),
        paused_businesses: Business.real_businesses.resource_paused.order(:name),
        archived_count: Business.real_businesses.resource_archived.count,
        active_count: Business.real_businesses.resource_active.count,
        auto_snooze_candidates: attention_rows.select { |row| row.resource_summary.auto_snooze_recommended }
      )
    end
  end
end
