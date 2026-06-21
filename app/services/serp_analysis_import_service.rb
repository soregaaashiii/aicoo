require "csv"
require "json"

class SerpAnalysisImportService
  Result = Data.define(:serp_analysis, :data_import)

  HIGH_AUTHORITY_DOMAINS = %w[
    wikipedia.org google.com tabelog.com hotpepper.jp gnavi.co.jp retty.me
    tripadvisor.jp navitime.co.jp map.yahoo.co.jp jalan.net rakuten.co.jp
    amazon.co.jp youtube.com instagram.com x.com
  ].freeze

  def initialize(business, keyword:, raw_text:, filename: "manual_serp.txt", location: nil, device: "desktop")
    @business = business
    @keyword = keyword.to_s.strip
    @raw_text = raw_text.to_s
    @filename = filename.presence || "manual_serp.txt"
    @location = location.to_s.strip
    @device = device.presence || "desktop"
  end

  def call
    raise ActiveRecord::RecordInvalid.new(SerpAnalysis.new.tap { |analysis| analysis.errors.add(:keyword, "can't be blank") }) if keyword.blank?
    raise ArgumentError, "SERP text is blank." if raw_text.blank?

    results = parse_results
    score = competition_score(results)
    data_import = create_data_import(results, score)
    analysis = create_analysis(results, score, data_import)

    Result.new(serp_analysis: analysis, data_import:)
  end

  private

  attr_reader :business, :keyword, :raw_text, :filename, :location, :device

  def parse_results
    csv_results.presence || line_results
  end

  def csv_results
    return [] unless File.extname(filename).casecmp(".csv").zero?

    CSV.parse(raw_text, headers: true).each_with_index.map do |row, index|
      {
        position: row["position"].presence&.to_i || index + 1,
        title: row["title"].to_s,
        url: row["url"].to_s,
        snippet: row["snippet"].to_s
      }
    end
  rescue CSV::MalformedCSVError
    []
  end

  def line_results
    raw_text.lines.map(&:strip).reject(&:blank?).first(20).each_with_index.map do |line, index|
      title, url, snippet = line.split(/\t|,/, 3).map(&:to_s)
      {
        position: index + 1,
        title: title.presence || line,
        url: url,
        snippet: snippet
      }
    end
  end

  def competition_score(results)
    count_score = [ results.size * 4, 40 ].min
    authority_score = [ results.count { |result| high_authority?(result[:url]) } * 10, 40 ].min
    title_score = [ results.count { |result| result[:title].to_s.include?(keyword) } * 5, 20 ].min

    [ count_score + authority_score + title_score, 100 ].min
  end

  def high_authority?(url)
    HIGH_AUTHORITY_DOMAINS.any? { |domain| url.to_s.include?(domain) }
  end

  def data_source
    @data_source ||= business.data_sources.find_or_create_by!(source_type: "serp", name: "SERP analysis") do |source|
      source.status = "active"
      source.notes = "Manual/CSV SERP research for competition estimation."
    end
  end

  def create_data_import(results, score)
    data_source.data_imports.create!(
      filename:,
      content_type: File.extname(filename).casecmp(".csv").zero? ? "text/csv" : "text/plain",
      row_count: results.size,
      raw_text:,
      processed_text: JSON.pretty_generate(processed_payload(results, score)),
      imported_at: Time.current
    )
  end

  def create_analysis(results, score, data_import)
    analysis = business.serp_analyses.create!(
      data_import:,
      keyword:,
      search_engine: "google",
      location:,
      device:,
      result_count: results.size,
      competition_score: score,
      summary: summary(results, score),
      analyzed_at: Time.current
    )

    results.each do |result|
      analysis.serp_results.create!(result)
    end

    analysis
  end

  def processed_payload(results, score)
    {
      source_type: "serp",
      keyword:,
      search_engine: "google",
      location:,
      device:,
      result_count: results.size,
      competition_score: score,
      summary: summary(results, score),
      results:
    }
  end

  def summary(results, score)
    high_authority_count = results.count { |result| high_authority?(result[:url]) }
    "keyword=#{keyword}, results=#{results.size}, high_authority_results=#{high_authority_count}, competition_score=#{score}"
  end
end
