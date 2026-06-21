namespace :aicoo do
  namespace :analytics do
    desc "Fetch enabled GA4/GSC analytics sources and record AnalyticsFetchRun results"
    task daily_fetch: :environment do
      started_at = Time.current
      enabled_count = AnalyticsSourceSetting.where(enabled: true).count
      before_run_id = AnalyticsFetchRun.maximum(:id).to_i

      puts "AICOO Analytics daily_fetch started_at=#{started_at.iso8601}"
      puts "有効なAnalyticsSourceSetting件数: #{enabled_count}"

      if enabled_count.zero?
        puts "有効なAnalytics設定がありません"
        puts "AICOO Analytics daily_fetch finished_at=#{Time.current.iso8601}"
        next
      end

      AicooAnalytics::DailyFetchJob.perform_now

      runs = AnalyticsFetchRun.where("id > ?", before_run_id)
      success_count = runs.where(status: "success").count
      failed_count = runs.where(status: "failed").count
      data_import_count = runs.where.not(data_import_id: nil).count
      snapshot_count = runs.sum(:snapshot_count)
      updated_neglect_loss_count = runs.sum(:updated_neglect_loss_count)

      puts "成功件数: #{success_count}"
      puts "失敗件数: #{failed_count}"
      puts "作成DataImport件数: #{data_import_count}"
      puts "Snapshot件数: #{snapshot_count}"
      puts "放置損失推定更新件数: #{updated_neglect_loss_count}"
      puts "AICOO Analytics daily_fetch finished_at=#{Time.current.iso8601}"
    end
  end
end
