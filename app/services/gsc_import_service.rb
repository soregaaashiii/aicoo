require "csv"
require "json"

class GscImportService
  Result = Data.define(:data_source, :data_import)

  def initialize(business, client: GscSearchAnalyticsClient.new, today: Date.current)
    @business = business
    @client = client
    @today = today
  end

  def call
    raise GscSearchAnalyticsClient::Error, "Business gsc_site_url is not set." if business.gsc_site_url.blank?

    response = client.query(site_url: business.gsc_site_url, start_date:, end_date:)
    rows = response.fetch("rows", [])
    data_source = find_or_create_data_source
    data_import = data_source.data_imports.create!(
      filename: filename,
      content_type: "text/csv",
      row_count: rows.size,
      raw_text: JSON.pretty_generate(response),
      processed_text: csv_text(rows),
      imported_at: Time.current
    )

    Result.new(data_source:, data_import:)
  end

  private

  attr_reader :business, :client, :today

  def start_date
    end_date - 27.days
  end

  def end_date
    today - 1.day
  end

  def filename
    "gsc_queries_#{start_date}_#{end_date}.csv"
  end

  def find_or_create_data_source
    business.data_sources.find_or_create_by!(source_type: "gsc", name: "Google Search Console") do |data_source|
      data_source.status = "active"
      data_source.notes = "site_url: #{business.gsc_site_url}"
    end
  end

  def csv_text(rows)
    CSV.generate(headers: true) do |csv|
      csv << %w[query clicks impressions ctr position]
      rows.each do |row|
        csv << [
          row.fetch("keys", []).first,
          row["clicks"],
          row["impressions"],
          row["ctr"],
          row["position"]
        ]
      end
    end
  end
end
