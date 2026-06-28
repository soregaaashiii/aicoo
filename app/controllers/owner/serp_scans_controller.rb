module Owner
  class SerpScansController < ApplicationController
    def create
      result = Aicoo::Serp::ScanRunner.new.call
      if result.failed_count.positive?
        redirect_to owner_focus_path,
                    alert: "SERP走査に失敗したクエリがあります。成功 #{result.success_count}件 / 失敗 #{result.failed_count}件"
      else
        redirect_to owner_focus_path,
                    notice: "SERP走査が完了しました。#{result.target_business_count} Business / #{result.query_count}クエリを確認しました。"
      end
    rescue StandardError => e
      redirect_to owner_focus_path, alert: "SERP走査に失敗しました: #{e.message}"
    end
  end
end
