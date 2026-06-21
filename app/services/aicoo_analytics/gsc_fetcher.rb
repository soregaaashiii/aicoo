require "csv"

module AicooAnalytics
  class GscFetcher
    Result = Data.define(:data_import, :pipeline_result)

    def initialize(setting, client: nil, today: Date.current)
      @setting = setting
      @client = client
      @today = today
    end

    def call
      raise GscSearchAnalyticsClient::Error, "GSC site_url is not set." if setting.site_url.blank?

      response = gsc_client.query(
        site_url: setting.site_url,
        start_date:,
        end_date:,
        dimensions: %w[query page date],
        row_limit: 1_000
      )
      csv = csv_text(response.fetch("rows", []))
      pipeline_result = ImportPipeline.new.create!(
        source_type: "gsc",
        filename: filename,
        raw_text: csv,
        run_after_import: true
      )
      data_import = DataImport.find(pipeline_result.data_import_id)
      data_import.update!(aicoo_analytics_site: setting.aicoo_analytics_site) if setting.aicoo_analytics_site
      setting.update!(last_fetched_at: Time.current)
      setting.aicoo_analytics_site&.update!(last_gsc_fetch_at: setting.last_fetched_at)

      Result.new(data_import:, pipeline_result:)
    end

    private

    attr_reader :setting, :client, :today

    def gsc_client
      client || GscSearchAnalyticsClient.new(oauth_client: token_client)
    end

    def token_client
      Struct.new(:setting) do
        def access_token
          AicooAnalytics::GoogleAccessToken.new(setting).call
        end
      end.new(setting)
    end

    def start_date
      end_date - (setting.fetch_days.to_i - 1).days
    end

    def end_date
      today - 1.day
    end

    def filename
      "gsc_api_#{setting.id}_#{start_date}_#{end_date}.csv"
    end

    def csv_text(rows)
      CSV.generate(headers: true) do |csv|
        csv << %w[date query page clicks impressions ctr position]
        rows.each do |row|
          keys = row.fetch("keys", [])
          csv << [
            keys[2],
            keys[0],
            keys[1],
            row["clicks"],
            row["impressions"],
            row["ctr"],
            row["position"]
          ]
        end
      end
    end
  end
end
