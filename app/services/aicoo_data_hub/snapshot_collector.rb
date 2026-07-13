require "json"
require "csv"

module AicooDataHub
  class SnapshotCollector
    Result = Data.define(:processed_count, :created_count, :failed_count) do
      def count = created_count

      def self.empty
        new(processed_count: 0, created_count: 0, failed_count: 0)
      end

      def +(other)
        self.class.new(
          processed_count: processed_count.to_i + other.processed_count.to_i,
          created_count: created_count.to_i + other.created_count.to_i,
          failed_count: failed_count.to_i + other.failed_count.to_i
        )
      end
    end

    def collect_all
      collect_data_imports + collect_landing_pages + collect_revenue
    end

    def collect_data_imports
      collect_ga4 + collect_gsc
    end

    def collect_ga4
      collect_data_imports_for("ga4")
    end

    def collect_gsc
      collect_data_imports_for("gsc")
    end

    def collect_landing_pages
      collect_records(AicooLabLandingPage.order(:id)) do |landing_page|
        create_snapshot_unless_exists(
          source_type: "landing_page",
          source_id: landing_page.id
        ) { landing_page_payload(landing_page) }
      end
    end

    def collect_revenue
      collect_records(AicooRevenueExecution.order(:id)) do |execution|
        create_snapshot_unless_exists(
          source_type: "revenue_execution",
          source_id: execution.id
        ) { revenue_payload(execution) }
      end
    end

    def collect_data_import(data_import)
      return Result.empty unless data_import

      source_type = data_import.data_source&.source_type
      return Result.empty unless %w[ga4 gsc].include?(source_type)

      collect_one do
        create_snapshot_unless_exists(
          source_type:,
          source_id: data_import.id
        ) { data_import_payload(data_import, source_type) }
      end
    end

    private

    def collect_data_imports_for(source_type)
      scope = DataImport.joins(:data_source).where(data_sources: { source_type: })
      collect_records(scope) do |data_import|
        create_snapshot_unless_exists(
          source_type:,
          source_id: data_import.id
        ) { data_import_payload(data_import, source_type) }
      end
    end

    def collect_records(scope)
      processed_count = 0
      created_count = 0
      failed_count = 0

      scope.find_each do |record|
        processed_count += 1
        created_count += 1 if yield(record)
      rescue StandardError => e
        failed_count += 1
        Rails.logger.warn("[AicooDataHub::SnapshotCollector] skipped record=#{record.class.name}##{record.id} #{e.class}: #{e.message}")
      end

      Result.new(processed_count:, created_count:, failed_count:)
    end

    def collect_one
      created = yield
      Result.new(processed_count: 1, created_count: created ? 1 : 0, failed_count: 0)
    rescue StandardError => e
      Rails.logger.warn("[AicooDataHub::SnapshotCollector] skipped single record #{e.class}: #{e.message}")
      Result.new(processed_count: 1, created_count: 0, failed_count: 1)
    end

    def create_snapshot_unless_exists(source_type:, source_id:)
      return false if snapshot_exists_today?(source_type, source_id)

      AicooDataSnapshot.create!(
        source_type:,
        source_id:,
        captured_at: Time.current,
        payload: yield
      )
      true
    end

    def snapshot_exists_today?(source_type, source_id)
      AicooDataSnapshot
        .where(source_type:, source_id:)
        .where(captured_at: Time.current.all_day)
        .exists?
    end

    def data_import_payload(data_import, source_type)
      parsed_raw_text = parse_raw_text(data_import.raw_text)
      metrics = source_type == "gsc" ? gsc_metrics(parsed_raw_text) : ga4_metrics(parsed_raw_text)

      {
        data_import_id: data_import.id,
        data_source_id: data_import.data_source_id,
        business_id: data_import.business&.id,
        analytics_site_id: data_import.aicoo_analytics_site_id,
        site_name: data_import.aicoo_analytics_site&.name,
        domain: data_import.aicoo_analytics_site&.domain,
        source_type:,
        filename: data_import.filename,
        content_type: data_import.content_type,
        row_count: data_import.row_count.to_i,
        imported_at: data_import.imported_at&.iso8601,
        metrics:,
        rows: parsed_rows(parsed_raw_text)
      }
    end

    def parsed_rows(parsed_raw_text)
      return [] unless parsed_raw_text.is_a?(Hash)

      Array(parsed_raw_text.fetch("rows", [])).select { |row| row.is_a?(Hash) }
    end

    def gsc_metrics(parsed_raw_text)
      rows = parsed_raw_text.is_a?(Hash) ? parsed_raw_text.fetch("rows", []) : []
      clicks = rows.sum { |row| row["clicks"].to_f }
      impressions = rows.sum { |row| row["impressions"].to_f }

      {
        clicks: number_or_integer(clicks),
        impressions: number_or_integer(impressions),
        ctr: impressions.positive? ? clicks / impressions : nil,
        position: average(rows.filter_map { |row| row["position"] })
      }
    end

    def ga4_metrics(parsed_raw_text)
      source = parsed_raw_text.is_a?(Hash) ? parsed_raw_text : {}
      rows = source.fetch("rows", [])
      if rows.present?
        return {
          page_views: sum_metric(rows, "page_views", "screenPageViews", "views"),
          users: sum_metric(rows, "users", "activeUsers", "totalUsers"),
          sessions: sum_metric(rows, "sessions")
        }
      end

      {
        page_views: metric_value(source, "page_views", "screenPageViews", "views"),
        users: metric_value(source, "users", "activeUsers", "totalUsers"),
        sessions: metric_value(source, "sessions")
      }
    end

    def landing_page_payload(landing_page)
      pv = landing_page.view_count
      cta_click = landing_page.cta_click_count
      signup = landing_page.signup_count

      {
        landing_page_id: landing_page.id,
        experiment_id: landing_page.aicoo_lab_experiment_id,
        pv:,
        cta_click:,
        signup:,
        cta_rate: rate(cta_click, pv),
        signup_rate: rate(signup, pv),
        sample_threshold_reached: landing_page.sample_threshold_reached?
      }
    end

    def revenue_payload(execution)
      {
        revenue_execution_id: execution.id,
        source_type: execution.source_type,
        source_id: execution.source_id,
        predicted_value: execution.predicted_value,
        actual_90d_profit_yen: execution.actual_90d_profit_yen,
        calibration_score: execution.calibration_score&.to_f,
        status: execution.status,
        measured_at: execution.measured_at&.iso8601
      }
    end

    def parse_raw_text(text)
      return {} if text.blank?

      JSON.parse(text)
    rescue JSON::ParserError
      parse_csv(text)
    end

    def parse_csv(text)
      rows = CSV.parse(text, headers: true).map(&:to_h)
      { "rows" => rows }
    rescue CSV::MalformedCSVError
      { "rows" => text.to_s.lines.map { |line| { "text" => line.strip } } }
    end

    def metric_value(source, *keys)
      keys.each do |key|
        value = source[key]
        return number_or_integer(value.to_f) if value.present?
      end

      nil
    end

    def sum_metric(rows, *keys)
      values = rows.filter_map do |row|
        key = keys.find { |candidate| row[candidate].present? }
        row[key].to_s.delete("%,").to_f if key
      end

      return nil if values.empty?

      number_or_integer(values.sum)
    end

    def average(values)
      numeric_values = values.map(&:to_f)
      return nil if numeric_values.empty?

      numeric_values.sum / numeric_values.size
    end

    def rate(numerator, denominator)
      return nil if denominator.to_i.zero?

      numerator.to_d / denominator.to_d
    end

    def number_or_integer(value)
      value == value.to_i ? value.to_i : value
    end
  end
end
