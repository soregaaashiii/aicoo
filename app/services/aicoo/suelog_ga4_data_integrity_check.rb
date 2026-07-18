require "csv"
require "set"

module Aicoo
  class SuelogGa4DataIntegrityCheck
    EXPECTED_BUSINESS_ID = Aicoo::SuelogGa4Resync::EXPECTED_BUSINESS_ID
    EXPECTED_PROPERTY_ID = Aicoo::SuelogGa4Resync::EXPECTED_PROPERTY_ID
    ALLOWED_HOSTS = Aicoo::SuelogGa4Resync::ALLOWED_HOSTS

    Result = Data.define(
      :business_id,
      :property_id,
      :host,
      :latest_fetch_status,
      :latest_success_at,
      :latest_failure_at,
      :oauth_usable,
      :stored_row_count,
      :article_row_count,
      :shop_row_count,
      :lp_row_count,
      :mixed_business_row_count,
      :stale_row_count,
      :ga4_matched_articles,
      :ga4_unmatched_articles,
      :ga4_article_match_rate,
      :fully_joinable_article_count,
      :integrity_status,
      :blocking_reasons
    )

    def self.call(...)
      new(...).call
    end

    def initialize(business: default_business, today: Date.current, expected_business_id: EXPECTED_BUSINESS_ID)
      @business = business
      @today = today.to_date
      @expected_business_id = expected_business_id
      @blocking_reasons = []
    end

    def call
      collect_blocking_reasons
      Result.new(
        business_id: business&.id,
        property_id: setting&.property_id,
        host: ALLOWED_HOSTS.join(","),
        latest_fetch_status: latest_fetch_status,
        latest_success_at: latest_success_at,
        latest_failure_at: latest_failure_at,
        oauth_usable: oauth_usable?,
        stored_row_count: rows.size,
        article_row_count: path_counts[:articles],
        shop_row_count: path_counts[:shops],
        lp_row_count: path_counts[:lp],
        mixed_business_row_count: mixed_business_rows.size,
        stale_row_count: stale_rows.size,
        ga4_matched_articles: article_match_summary[:matched_article_ids].size,
        ga4_unmatched_articles: article_match_summary[:unmatched_article_count],
        ga4_article_match_rate: article_match_rate,
        fully_joinable_article_count: article_match_summary[:matched_article_ids].size,
        integrity_status: integrity_status,
        blocking_reasons: blocking_reasons.uniq
      )
    end

    private

    attr_reader :business, :today, :expected_business_id, :blocking_reasons

    def default_business
      Business.kept.find_by(id: EXPECTED_BUSINESS_ID) || Business.kept.find_by(name: "吸えログ")
    end

    def collect_blocking_reasons
      blocking_reasons << "suelog_business_not_found" if business.blank?
      blocking_reasons << "business_id_mismatch" if business && business.id != expected_business_id
      blocking_reasons << "ga4_setting_not_found" if setting.blank?
      blocking_reasons << "oauth_expired_or_unusable" unless oauth_usable?
      blocking_reasons << "property_id_mismatch" if setting && setting.property_id.to_s != EXPECTED_PROPERTY_ID
      blocking_reasons << "latest_ga4_fetch_not_success" unless latest_fetch_status == "success"
      blocking_reasons << "article_row_count_zero" if path_counts[:articles].zero?
      blocking_reasons << "ga4_matched_articles_zero" if article_match_summary[:matched_article_ids].empty?
      blocking_reasons << "mixed_business_data" if mixed_business_rows.any?
      blocking_reasons << "stale_data_only" if rows.any? && rows.all? { |row| stale_row?(row) }
      blocking_reasons << "wrong_host_saved" if wrong_host_rows.any?
    end

    def integrity_status
      fail_reasons = %w[
        suelog_business_not_found
        business_id_mismatch
        ga4_setting_not_found
        oauth_expired_or_unusable
        property_id_mismatch
        latest_ga4_fetch_not_success
        article_row_count_zero
        ga4_matched_articles_zero
        mixed_business_data
        wrong_host_saved
        stale_data_only
      ]
      return "fail" if (blocking_reasons & fail_reasons).any?
      return "warning" if article_match_summary[:unmatched_article_count].positive?

      "pass"
    end

    def latest_fetch_status
      latest_fetch&.status || latest_google_run&.status || "missing"
    end

    def latest_success_at
      ([ latest_success_fetch&.finished_at, latest_success_google_run&.finished_at ].compact.max)&.iso8601
    end

    def latest_failure_at
      ([ latest_failed_fetch&.finished_at, latest_failed_google_run&.finished_at ].compact.max)&.iso8601
    end

    def latest_fetch
      @latest_fetch ||= AnalyticsFetchRun.where(analytics_source_setting: setting, source_type: "ga4").recent.first if setting
    end

    def latest_success_fetch
      @latest_success_fetch ||= AnalyticsFetchRun.where(analytics_source_setting: setting, source_type: "ga4", status: "success").recent.first if setting
    end

    def latest_failed_fetch
      @latest_failed_fetch ||= AnalyticsFetchRun.where(analytics_source_setting: setting, source_type: "ga4", status: "failed").recent.first if setting
    end

    def latest_google_run
      @latest_google_run ||= GoogleApiImportRun.where(business:).recent.first if business
    end

    def latest_success_google_run
      @latest_success_google_run ||= GoogleApiImportRun.where(business:, status: "success").recent.first if business
    end

    def latest_failed_google_run
      @latest_failed_google_run ||= GoogleApiImportRun.where(business:, status: "failed").recent.first if business
    end

    def setting
      @setting ||= begin
        AnalyticsSourceSetting.where(source_type: "ga4", property_id: EXPECTED_PROPERTY_ID, enabled: true).find do |row|
          row.aicoo_analytics_site&.business_id == business&.id || row.name.to_s.include?("吸えログ")
        end || AicooAnalyticsSite.where(business:, ga4_property_id: EXPECTED_PROPERTY_ID).recent.first&.ga4_setting
      end
    end

    def oauth_usable?
      credential = setting&.google_credential || AicooGoogleCredential.default
      credential.present? && credential.enabled? && (credential.refresh_token.present? || setting&.refresh_token.present?)
    end

    def rows
      @rows ||= normalize_rows(data_imports.flat_map { |data_import| rows_from_import(data_import) } + snapshots.flat_map { |snapshot| rows_from_snapshot(snapshot) })
    end

    def data_imports
      @data_imports ||= begin
        return [] unless business

        DataImport
          .joins(:data_source)
          .where(data_sources: { business_id: business.id, source_type: "ga4" })
          .includes(:data_source, :aicoo_analytics_site)
          .recent
          .limit(20)
          .to_a
      end
    end

    def snapshots
      @snapshots ||= begin
        import_ids = data_imports.map(&:id)
        AicooDataSnapshot.where(source_type: "ga4", source_id: import_ids).recent.limit(20).to_a
      end
    end

    def rows_from_import(data_import)
      parse_csv(data_import.processed_text.presence || data_import.raw_text).map do |row|
        row.merge(
          "business_id" => data_import.business&.id,
          "property_id" => property_id_from_import(data_import),
          "source_model" => "DataImport",
          "source_id" => data_import.id,
          "imported_at" => data_import.imported_at&.iso8601
        )
      end
    end

    def rows_from_snapshot(snapshot)
      payload = snapshot.payload.to_h.deep_stringify_keys
      Array(payload["rows"]).map do |row|
        row.to_h.deep_stringify_keys.merge(
          "business_id" => payload["business_id"],
          "property_id" => payload["property_id"],
          "source_model" => "AicooDataSnapshot",
          "source_id" => snapshot.id,
          "captured_at" => snapshot.captured_at&.iso8601
        )
      end
    end

    def normalize_rows(source_rows)
      source_rows.filter_map do |row|
        page = row["pagePath"].presence || row["page_path"].presence || row["page"].presence
        next if page.blank?

        row.merge(
          "normalized_page" => Aicoo::UrlNormalizer.call(page),
          "hostName" => row["hostName"].presence || row["host_name"].presence,
          "business_id" => row["business_id"],
          "property_id" => row["property_id"].presence || EXPECTED_PROPERTY_ID
        )
      end
    end

    def parse_csv(text)
      return [] if text.blank?

      CSV.parse(text, headers: true).map { |row| row.to_h.deep_stringify_keys }
    rescue CSV::MalformedCSVError
      []
    end

    def property_id_from_import(data_import)
      data_import.aicoo_analytics_site&.ga4_property_id || setting&.property_id
    end

    def path_counts
      @path_counts ||= begin
        counts = { articles: 0, shops: 0, lp: 0, other: 0 }
        correct_rows.each do |row|
          case row["normalized_page"]
          when %r{\A/articles/} then counts[:articles] += 1
          when %r{\A/shops/} then counts[:shops] += 1
          when %r{\A/lp(?:/|\z)} then counts[:lp] += 1
          else counts[:other] += 1 if row["normalized_page"].present?
          end
        end
        counts
      end
    end

    def correct_rows
      rows.reject { |row| mixed_business_row?(row) || wrong_host_row?(row) }
    end

    def mixed_business_rows
      @mixed_business_rows ||= rows.select { |row| mixed_business_row?(row) }
    end

    def mixed_business_row?(row)
      row["business_id"].present? && row["business_id"].to_i != business.id
    end

    def wrong_host_rows
      @wrong_host_rows ||= rows.select { |row| wrong_host_row?(row) }
    end

    def wrong_host_row?(row)
      host = row["hostName"].to_s.downcase
      host.present? && !ALLOWED_HOSTS.include?(host)
    end

    def stale_rows
      @stale_rows ||= rows.select { |row| stale_row?(row) }
    end

    def stale_row?(row)
      time = Time.zone.parse(row["imported_at"].presence || row["captured_at"].presence || "")
      time.present? && time < 14.days.ago
    rescue ArgumentError
      false
    end

    def article_match_summary
      @article_match_summary ||= begin
        articles = suelog_articles
        matcher = Aicoo::ArticleUrlMatcher.new(articles:)
        matched_article_ids = Set.new
        correct_rows.select { |row| row["normalized_page"].to_s.start_with?("/articles/") }.each do |row|
          match = matcher.match(row["normalized_page"])
          matched_article_ids << match.article_id if match.article_id.present?
        end
        {
          matched_article_ids:,
          article_count: articles.size,
          unmatched_article_count: [ articles.size - matched_article_ids.size, 0 ].max
        }
      rescue StandardError => e
        blocking_reasons << "article_match_error=#{e.class}: #{e.message}"
        { matched_article_ids: Set.new, article_count: 0, unmatched_article_count: 0 }
      end
    end

    def article_match_rate
      count = article_match_summary[:article_count].to_i
      return 0 if count.zero?

      ((article_match_summary[:matched_article_ids].size.to_d / count) * 100).round(1)
    end

    def suelog_articles
      return [] unless defined?(::Suelog::Article)

      scope = ::Suelog::Article.all
      scope = scope.where(published: true) if ::Suelog::Article.column_names.include?("published")
      scope = scope.where("published_at IS NULL OR published_at <= ?", Time.current) if ::Suelog::Article.column_names.include?("published_at")
      scope.limit(500).to_a
    end
  end
end
