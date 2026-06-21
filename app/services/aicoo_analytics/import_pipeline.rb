module AicooAnalytics
  class ImportPipeline
    SOURCE_TYPES = %w[ga4 gsc].freeze
    Result = Data.define(:data_import_id, :snapshot_count, :updated_neglect_loss_count, :skipped_count)

    def create!(source_type:, filename:, raw_text:, run_after_import: true)
      data_import = analytics_data_source(source_type).data_imports.create!(
        filename: filename.presence || default_filename(source_type),
        raw_text:,
        processed_text: raw_text,
        row_count: row_count(raw_text),
        content_type: "text/csv",
        imported_at: Time.current
      )

      run_after_import ? reprocess(data_import) : empty_result(data_import)
    end

    def reprocess(data_import)
      snapshot_result = AicooDataHub::SnapshotCollector.new.collect_data_imports
      neglect_result = update_neglect_loss_estimates

      Result.new(
        data_import_id: data_import.id,
        snapshot_count: snapshot_result.count,
        updated_neglect_loss_count: neglect_result.fetch(:updated_count),
        skipped_count: neglect_result.fetch(:skipped_count)
      )
    end

    private

    def analytics_data_source(source_type)
      type = source_type.presence_in(SOURCE_TYPES) || "ga4"
      business = Business.find_or_create_by!(name: "AICOO Analytics Import") do |record|
        record.description = "GA4/GSCの貼り付けデータをAICOOに取り込むための管理用フォルダです。"
        record.status = "launched"
      end

      business.data_sources.find_or_create_by!(source_type: type) do |record|
        record.name = "#{type.upcase}貼り付けデータ"
        record.status = "active"
        record.notes = "外部API連携なしで貼り付けた#{type.upcase}データです。"
      end
    end

    def update_neglect_loss_estimates
      records = [
        ActionCandidate.all,
        AicooLabExperimentCandidate.all,
        AicooLabExperiment.all
      ]

      updated_count = 0
      skipped_count = 0

      records.each do |scope|
        scope.find_each do |record|
          result = AicooRevenue::NeglectLossEstimator.new(record).estimate_and_store!
          if result.auto_generated
            updated_count += 1
          else
            skipped_count += 1
          end
        end
      end

      { updated_count:, skipped_count: }
    end

    def empty_result(data_import)
      Result.new(
        data_import_id: data_import.id,
        snapshot_count: 0,
        updated_neglect_loss_count: 0,
        skipped_count: 0
      )
    end

    def row_count(raw_text)
      raw_text.to_s.lines.count
    end

    def default_filename(source_type)
      "#{source_type}-#{Time.current.strftime('%Y%m%d%H%M%S')}.csv"
    end
  end
end
