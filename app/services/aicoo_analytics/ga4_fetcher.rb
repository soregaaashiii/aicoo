require "csv"

module AicooAnalytics
  class Ga4Fetcher
    Result = Data.define(:data_import, :pipeline_result)

    def initialize(setting, client: nil, today: Date.current)
      @setting = setting
      @client = client
      @today = today
    end

    def call
      raise Ga4DataApiClient::Error, "GA4 property_id is not set." if setting.property_id.blank?

      response = ga4_client.run_report(property_id: setting.property_id, start_date:, end_date:)
      csv = csv_text(response.fetch("rows", []))
      pipeline_result = ImportPipeline.new.create!(
        source_type: "ga4",
        filename: filename,
        raw_text: csv,
        run_after_import: true
      )
      data_import = DataImport.find(pipeline_result.data_import_id)
      data_import.update!(aicoo_analytics_site: setting.aicoo_analytics_site) if setting.aicoo_analytics_site
      setting.update!(last_fetched_at: Time.current)
      setting.aicoo_analytics_site&.update!(last_ga4_fetch_at: setting.last_fetched_at)

      Result.new(data_import:, pipeline_result:)
    end

    private

    attr_reader :setting, :client, :today

    def ga4_client
      client || Ga4DataApiClient.new(access_token: GoogleAccessToken.new(setting).call)
    end

    def start_date
      end_date - (setting.fetch_days.to_i - 1).days
    end

    def end_date
      today - 1.day
    end

    def filename
      "ga4_api_#{setting.id}_#{start_date}_#{end_date}.csv"
    end

    def csv_text(rows)
      CSV.generate(headers: true) do |csv|
        csv << %w[date pagePath screenPageViews activeUsers sessions eventCount]
        rows.each do |row|
          dimensions = row.fetch("dimensionValues", [])
          metrics = row.fetch("metricValues", [])
          csv << [
            dimensions.dig(0, "value"),
            dimensions.dig(1, "value"),
            metrics.dig(0, "value"),
            metrics.dig(1, "value"),
            metrics.dig(2, "value"),
            metrics.dig(3, "value")
          ]
        end
      end
    end
  end
end
