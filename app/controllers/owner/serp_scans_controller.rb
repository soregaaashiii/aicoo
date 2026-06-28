module Owner
  class SerpScansController < ApplicationController
    def create
      result = Aicoo::Serp::ScanRunner.new.call
      if result.failed_count.positive?
        redirect_to owner_focus_path,
                    alert: "SERP走査に失敗したクエリがあります。成功 #{result.success_count}件 / 失敗 #{result.failed_count}件"
      else
        redirect_to owner_focus_path,
                    notice: "SERP走査が完了しました。#{result.target_business_count} Business / #{result.query_count}クエリ / #{result.result_count}件取得 / 約#{result.estimated_cost_yen}円 / #{result.duration_seconds}秒"
      end
    rescue StandardError => e
      redirect_to owner_focus_path, alert: "SERP走査に失敗しました: #{e.message}"
    end

    def update_settings
      limit = Aicoo::Serp::ScanPlan.save_limit!(params.dig(:serp_scan, :limit))
      redirect_to owner_focus_path, notice: "SERP走査Limitを#{limit}に保存しました。"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to owner_focus_path, alert: "SERP走査Limitを保存できませんでした: #{e.record.errors.full_messages.to_sentence}"
    end
  end
end
