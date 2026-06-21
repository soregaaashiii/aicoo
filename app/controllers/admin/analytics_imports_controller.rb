module Admin
  class AnalyticsImportsController < ApplicationController
    SOURCE_TYPES = %w[ga4 gsc].freeze

    def index
      @data_imports = DataImport.joins(:data_source)
                                .where(data_sources: { source_type: SOURCE_TYPES })
                                .includes(:data_source)
                                .recent
                                .limit(50)
      @source_type = params[:source_type].presence_in(SOURCE_TYPES) || "ga4"
    end

    def create
      result = AicooAnalytics::ImportPipeline.new.create!(
        source_type: analytics_import_params[:source_type],
        filename: analytics_import_params[:filename],
        raw_text: analytics_import_params[:raw_text],
        run_after_import: run_after_import?
      )
      data_import = DataImport.find(result.data_import_id)

      redirect_to admin_analytics_imports_path, notice: completion_message(data_import, result)
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_analytics_imports_path(source_type: analytics_import_params[:source_type]), alert: "取込に失敗しました: #{e.message}"
    end

    def reprocess
      data_import = DataImport.find(params.expect(:id))
      result = AicooAnalytics::ImportPipeline.new.reprocess(data_import)

      redirect_to admin_analytics_imports_path, notice: "再処理しました。Snapshot #{result.snapshot_count}件作成、放置損失推定 #{result.updated_neglect_loss_count}件更新しました。"
    end

    private

    def analytics_import_params
      params.expect(analytics_import: [ :source_type, :filename, :raw_text, :run_after_import ])
    end

    def run_after_import?
      analytics_import_params[:run_after_import] != "0"
    end

    def completion_message(data_import, result)
      base = "#{data_import.data_source.source_type.upcase}データを保存しました。"
      return base if result.snapshot_count.zero? && result.updated_neglect_loss_count.zero? && result.skipped_count.zero?

      "#{base}Snapshot #{result.snapshot_count}件作成、放置損失推定 #{result.updated_neglect_loss_count}件更新しました。"
    end
  end
end
