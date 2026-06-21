require "json"
require "csv"

module AicooDataHub
  class SnapshotCollector
    Result = Data.define(:snapshots) do
      def count
        snapshots.size
      end
    end

    def collect_all
      Result.new(snapshots: collect_data_imports.snapshots + collect_landing_pages.snapshots + collect_revenue.snapshots)
    end

    def collect_data_imports
      Result.new(snapshots: collect_ga4.snapshots + collect_gsc.snapshots)
    end

    def collect_ga4
      collect_data_imports_for("ga4")
    end

    def collect_gsc
      collect_data_imports_for("gsc")
    end

    def collect_landing_pages
      snapshots = AicooLabLandingPage.find_each.filter_map do |landing_page|
        create_snapshot(
          source_type: "landing_page",
          source_id: landing_page.id,
          payload: landing_page_payload(landing_page)
        )
      end

      Result.new(snapshots:)
    end

    def collect_revenue
      snapshots = AicooRevenueExecution.find_each.filter_map do |execution|
        create_snapshot(
          source_type: "revenue_execution",
          source_id: execution.id,
          payload: revenue_payload(execution)
        )
      end

      Result.new(snapshots:)
    end

    private

    def collect_data_imports_for(source_type)
      snapshots = DataImport.joins(:data_source).where(data_sources: { source_type: }).find_each.filter_map do |data_import|
        create_snapshot(
          source_type:,
          source_id: data_import.id,
          payload: data_import_payload(data_import, source_type)
        )
      end

      Result.new(snapshots:)
    end

    def create_snapshot(source_type:, source_id:, payload:)
      return if snapshot_exists_today?(source_type, source_id)

      AicooDataSnapshot.create!(
        source_type:,
        source_id:,
        captured_at: Time.current,
        payload:
      )
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
