require "csv"

module Aicoo
  class SuelogGa4Resync
    EXPECTED_BUSINESS_ID = 2
    EXPECTED_PROPERTY_ID = "543499803"
    ALLOWED_HOSTS = %w[suelog.jp www.suelog.jp].freeze
    DIMENSIONS = %w[date pagePath hostName pageLocation].freeze
    METRICS = %w[
      screenPageViews
      activeUsers
      sessions
      eventCount
      userEngagementDuration
      engagementRate
      keyEvents
    ].freeze

    Result = Data.define(
      :mode,
      :oauth_usable,
      :property_matches_suelog,
      :business_matches_suelog,
      :resync_allowed,
      :blocking_reasons,
      :business,
      :setting,
      :start_date,
      :end_date,
      :api_row_count,
      :saved_row_count,
      :article_row_count,
      :shop_row_count,
      :lp_row_count,
      :host_counts,
      :excluded_counts,
      :accepted_reason_counts,
      :rejected_reason_counts,
      :row_diagnostics,
      :data_import_id,
      :snapshot_id,
      :analytics_fetch_run_id,
      :google_api_import_run_id
    )

    def self.call(...)
      new(...).call
    end

    def initialize(business: default_business, apply: false, today: Date.current, client: nil, access_token: nil, expected_business_id: EXPECTED_BUSINESS_ID)
      @business = business
      @apply = ActiveModel::Type::Boolean.new.cast(apply)
      @today = today.to_date
      @client = client
      @access_token = access_token
      @expected_business_id = expected_business_id
      @blocking_reasons = []
    end

    def call
      preflight = preflight_result
      return result_from_preflight(preflight) unless preflight.fetch(:resync_allowed)

      response = ga4_client.run_report(
        property_id: setting.property_id,
        start_date:,
        end_date:,
        dimensions: DIMENSIONS,
        metrics: METRICS,
        limit: 10_000
      )
      rows = normalize_api_rows(Array(response["rows"]))
      accepted_rows, excluded_counts, row_diagnostics = filter_rows(rows)

      return dry_run_result(accepted_rows:, excluded_counts:, row_diagnostics:) unless apply

      persisted = persist!(accepted_rows:, api_row_count: rows.size, excluded_counts:)
      build_result(
        accepted_rows:,
        api_row_count: rows.size,
        excluded_counts:,
        row_diagnostics:,
        data_import_id: persisted.fetch(:data_import).id,
        snapshot_id: persisted.fetch(:snapshot)&.id,
        analytics_fetch_run_id: persisted.fetch(:analytics_fetch_run).id,
        google_api_import_run_id: persisted.fetch(:google_api_import_run).id
      )
    rescue StandardError => e
      blocking_reasons << "#{e.class}: #{e.message}"
      mark_failed_runs(e)
      build_result(accepted_rows: [], api_row_count: 0, excluded_counts: Hash.new(0), row_diagnostics: [], resync_allowed: false)
    end

    private

    attr_reader :business, :apply, :today, :client, :access_token, :expected_business_id, :blocking_reasons

    def default_business
      Business.kept.find_by(id: EXPECTED_BUSINESS_ID) || Business.kept.find_by(name: "吸えログ")
    end

    def preflight_result
      if business.blank?
        blocking_reasons << "suelog_business_not_found"
        return preflight_hash(false)
      end

      blocking_reasons << "business_id_mismatch" unless business.id == expected_business_id
      blocking_reasons << "business_name_mismatch" unless business.name.to_s.include?("吸えログ")
      blocking_reasons << "ga4_setting_not_found" if setting.blank?
      blocking_reasons << "business_data_source_setting_disabled" if business_source_setting && !business_source_setting.enabled?
      blocking_reasons << "analytics_source_setting_disabled" if setting && !setting.enabled?
      blocking_reasons << "property_id_mismatch" unless property_matches_suelog?
      blocking_reasons << "host_not_suelog" unless setting_host_matches_suelog?
      blocking_reasons << "google_credential_not_found" if credential.blank?
      blocking_reasons << "refresh_token_not_found" if credential && credential.refresh_token.blank? && setting.refresh_token.blank?

      verify_access_token! if blocking_reasons.empty?
      preflight_hash(blocking_reasons.empty?)
    end

    def preflight_hash(allowed)
      {
        oauth_usable: oauth_usable?,
        property_matches_suelog: property_matches_suelog?,
        business_matches_suelog: business&.id == expected_business_id,
        resync_allowed: allowed,
        blocking_reasons: blocking_reasons.uniq
      }
    end

    def verify_access_token!
      resolved_access_token
      @oauth_usable = true
    rescue StandardError => e
      @oauth_usable = false
      blocking_reasons << "oauth_access_token_error=#{e.class}: #{e.message}"
    end

    def oauth_usable?
      return @oauth_usable if defined?(@oauth_usable)

      credential.present? && (credential.refresh_token.present? || setting&.refresh_token.present?)
    end

    def setting
      @setting ||= begin
        identifier = business_source_setting&.connection_field_value("property_id").presence ||
                     business_source_setting&.property_identifier.presence ||
                     EXPECTED_PROPERTY_ID
        scope = AnalyticsSourceSetting.where(source_type: "ga4")
        scope.find_by(property_id: identifier, enabled: true) || analytics_site&.ga4_setting
      end
    end

    def analytics_site
      @analytics_site ||= AicooAnalyticsSite.where(business:).where(ga4_property_id: EXPECTED_PROPERTY_ID).recent.first ||
                          AicooAnalyticsSite.where(business:).recent.first
    end

    def business_source_setting
      @business_source_setting ||= BusinessDataSourceSetting.find_by(business:, source_key: "ga4")
    end

    def credential
      @credential ||= setting&.google_credential || AicooGoogleCredential.default
    end

    def property_matches_suelog?
      setting&.property_id.to_s == EXPECTED_PROPERTY_ID
    end

    def setting_host_matches_suelog?
      hosts = [
        analytics_site&.domain,
        host_from_url(analytics_site&.public_url),
        host_from_url(business_source_setting&.endpoint_url),
        business_source_setting&.connection_field_value("host"),
        business_source_setting&.connection_field_value("domain")
      ].compact_blank.map { |host| normalize_host(host) }
      hosts.empty? || hosts.any? { |host| ALLOWED_HOSTS.include?(host) }
    end

    def ga4_client
      client || AicooAnalytics::Ga4DataApiClient.new(access_token: resolved_access_token)
    end

    def resolved_access_token
      @resolved_access_token ||= access_token.presence || AicooAnalytics::GoogleAccessToken.new(setting).call
    end

    def start_date
      today - 90.days
    end

    def end_date
      today - 1.day
    end

    def normalize_api_rows(rows)
      rows.filter_map do |row|
        dimensions = Array(row["dimensionValues"]).map { |value| value.to_h["value"] }
        metrics = Array(row["metricValues"]).map { |value| value.to_h["value"] }
        dimension_map = DIMENSIONS.zip(dimensions).to_h
        page_path = dimension_map["pagePath"].to_s
        host = dimension_map["hostName"].to_s
        page_location = dimension_map["pageLocation"].to_s
        next if dimensions.blank?

        {
          "date" => dimensions[0],
          "pagePath" => page_path,
          "hostName" => host,
          "pageLocation" => page_location,
          "dimensionValues" => dimension_map,
          "screenPageViews" => metrics[0].to_i,
          "activeUsers" => metrics[1].to_i,
          "sessions" => metrics[2].to_i,
          "eventCount" => metrics[3].to_i,
          "userEngagementDuration" => metrics[4].to_i,
          "engagementRate" => metrics[5].to_d,
          "keyEvents" => metrics[6].to_i
        }
      rescue StandardError
        nil
      end
    end

    def filter_rows(rows)
      excluded_counts = Hash.new(0)
      diagnostics = []
      accepted = rows.each_with_index.filter_map do |row, index|
        page_path = row["pagePath"].to_s
        host_decision = host_acceptance(row)
        diagnostics << diagnostic_row(index, row, host_decision)
        if page_path.blank?
          excluded_counts[:blank_page_path] += 1
          next
        end
        unless host_decision.fetch(:accepted)
          excluded_counts[host_decision.fetch(:reason)] += 1
          next
        end

        row.merge(
          "hostName" => host_decision.fetch(:resolved_host).presence || row["hostName"],
          "host_acceptance_reason" => host_decision.fetch(:reason)
        )
      end
      [ accepted, excluded_counts, diagnostics ]
    end

    def persist!(accepted_rows:, api_row_count:, excluded_counts:)
      raise "resync_not_allowed" unless preflight_result.fetch(:resync_allowed)

      ActiveRecord::Base.transaction do
        google_run = GoogleApiImportRun.create!(
          business:,
          status: "running",
          source_types: [ "ga4" ],
          fetched_days: 90,
          started_at: Time.current,
          metadata: resync_metadata(api_row_count:, accepted_rows:, excluded_counts:)
        )
        analytics_run = setting.analytics_fetch_runs.create!(
          status: "running",
          source_type: "ga4",
          started_at: Time.current
        )
        data_import = ga4_data_source.data_imports.create!(
          aicoo_analytics_site: analytics_site || setting.aicoo_analytics_site,
          filename: "suelog_ga4_resync_#{start_date}_#{end_date}.csv",
          raw_text: csv_text(accepted_rows),
          processed_text: csv_text(accepted_rows),
          row_count: accepted_rows.size,
          content_type: "text/csv",
          imported_at: Time.current
        )
        snapshot = AicooDataHub::SnapshotCollector.new.collect_data_import(data_import)
        snapshot_record = AicooDataSnapshot.where(source_type: "ga4", source_id: data_import.id).recent.first

        setting.update!(last_fetched_at: Time.current)
        (analytics_site || setting.aicoo_analytics_site)&.update!(last_ga4_fetch_at: setting.last_fetched_at)
        analytics_run.update!(
          status: "success",
          finished_at: Time.current,
          data_import_id: data_import.id,
          snapshot_count: snapshot.created_count,
          updated_neglect_loss_count: 0,
          error_message: nil
        )
        google_run.update!(
          status: "success",
          finished_at: Time.current,
          duration_seconds: (Time.current - google_run.started_at).round(2),
          updated_metric_count: accepted_rows.size,
          error_message: nil,
          metadata: google_run.metadata.merge(resync_metadata(api_row_count:, accepted_rows:, excluded_counts:))
        )
        { google_api_import_run: google_run, analytics_fetch_run: analytics_run, data_import:, snapshot: snapshot_record }
      end
    end

    def ga4_data_source
      business.data_sources.find_or_create_by!(source_type: "ga4") do |source|
        source.name = "吸えログ GA4再同期"
        source.status = "active"
        source.notes = "吸えログBusiness専用のGA4再同期データです。"
      end
    end

    def csv_text(rows)
      CSV.generate(headers: true) do |csv|
        csv << %w[date pagePath hostName pageLocation screenPageViews activeUsers sessions eventCount userEngagementDuration engagementRate keyEvents business_id property_id resync_source host_acceptance_reason]
        rows.each do |row|
          csv << [
            row["date"],
            row["pagePath"],
            row["hostName"],
            row["pageLocation"],
            row["screenPageViews"],
            row["activeUsers"],
            row["sessions"],
            row["eventCount"],
            row["userEngagementDuration"],
            row["engagementRate"],
            row["keyEvents"],
            business.id,
            setting.property_id,
            "suelog_ga4_resync",
            row["host_acceptance_reason"]
          ]
        end
      end
    end

    def resync_metadata(api_row_count:, accepted_rows:, excluded_counts:)
      path_counts = path_category_counts(accepted_rows.map { |row| row["pagePath"] })
      {
        "business_id" => business.id,
        "property_id" => setting.property_id,
        "host" => ALLOWED_HOSTS.join(","),
        "fetch_started_at" => Time.current.iso8601,
        "fetch_finished_at" => Time.current.iso8601,
        "date_range" => { "start_date" => start_date.to_s, "end_date" => end_date.to_s },
        "api_row_count" => api_row_count,
        "saved_row_count" => accepted_rows.size,
        "article_row_count" => path_counts[:articles],
        "shop_row_count" => path_counts[:shops],
        "lp_row_count" => path_counts[:lp],
        "source_setting_id" => setting.id,
        "resync_run_id" => SecureRandom.uuid,
        "excluded_counts" => excluded_counts.transform_keys(&:to_s)
      }
    end

    def dry_run_result(accepted_rows:, excluded_counts:, row_diagnostics:)
      build_result(accepted_rows:, api_row_count: accepted_rows.size + excluded_counts.values.sum, excluded_counts:, row_diagnostics:)
    end

    def result_from_preflight(preflight)
      Result.new(
        mode: apply ? "apply" : "dry-run",
        oauth_usable: preflight.fetch(:oauth_usable),
        property_matches_suelog: preflight.fetch(:property_matches_suelog),
        business_matches_suelog: preflight.fetch(:business_matches_suelog),
        resync_allowed: preflight.fetch(:resync_allowed),
        blocking_reasons: preflight.fetch(:blocking_reasons),
        business:,
        setting:,
        start_date: start_date,
        end_date: end_date,
        api_row_count: 0,
        saved_row_count: 0,
        article_row_count: 0,
        shop_row_count: 0,
        lp_row_count: 0,
        host_counts: {},
        excluded_counts: {},
        accepted_reason_counts: {},
        rejected_reason_counts: {},
        row_diagnostics: [],
        data_import_id: nil,
        snapshot_id: nil,
        analytics_fetch_run_id: nil,
        google_api_import_run_id: nil
      )
    end

    def build_result(accepted_rows:, api_row_count:, excluded_counts:, row_diagnostics: [], resync_allowed: true, data_import_id: nil, snapshot_id: nil, analytics_fetch_run_id: nil, google_api_import_run_id: nil)
      preflight = preflight_result
      path_counts = path_category_counts(accepted_rows.map { |row| row["pagePath"] })
      Result.new(
        mode: apply ? "apply" : "dry-run",
        oauth_usable: preflight.fetch(:oauth_usable),
        property_matches_suelog: preflight.fetch(:property_matches_suelog),
        business_matches_suelog: preflight.fetch(:business_matches_suelog),
        resync_allowed: resync_allowed && preflight.fetch(:resync_allowed),
        blocking_reasons: blocking_reasons.uniq,
        business:,
        setting:,
        start_date:,
        end_date:,
        api_row_count:,
        saved_row_count: accepted_rows.size,
        article_row_count: path_counts[:articles],
        shop_row_count: path_counts[:shops],
        lp_row_count: path_counts[:lp],
        host_counts: accepted_rows.group_by { |row| row["hostName"].presence || "-" }.transform_values(&:size),
        excluded_counts: excluded_counts.transform_keys(&:to_s),
        accepted_reason_counts: accepted_rows.group_by { |row| row["host_acceptance_reason"].presence || "unknown" }.transform_values(&:size),
        rejected_reason_counts: row_diagnostics.reject { |row| row.fetch(:accepted) }.group_by { |row| row.fetch(:exclude_reason).presence || "unknown" }.transform_values(&:size),
        row_diagnostics:,
        data_import_id:,
        snapshot_id:,
        analytics_fetch_run_id:,
        google_api_import_run_id:
      )
    end

    def mark_failed_runs(error)
      return unless defined?(@analytics_run) || defined?(@google_run)

      @analytics_run&.update!(status: "failed", finished_at: Time.current, error_message: error.message)
      @google_run&.update!(status: "failed", finished_at: Time.current, error_message: error.message)
    end

    def path_category_counts(paths)
      counts = { articles: 0, shops: 0, lp: 0, other: 0 }
      paths.each do |path|
        normalized = Aicoo::UrlNormalizer.call(path)
        case normalized
        when %r{\A/articles/} then counts[:articles] += 1
        when %r{\A/shops/} then counts[:shops] += 1
        when %r{\A/lp(?:/|\z)} then counts[:lp] += 1
        else counts[:other] += 1 if normalized.present?
        end
      end
      counts
    end

    def host_acceptance(row)
      page_path = row["pagePath"].to_s
      host_from_hostname = normalize_host(row["hostName"])
      host_from_location = normalize_host(host_from_url(row["pageLocation"]))

      if host_from_hostname.present?
        return host_decision(host_from_hostname, :host_name_match) if ALLOWED_HOSTS.include?(host_from_hostname)
        return { accepted: false, reason: :wrong_host, resolved_host: host_from_hostname, match_source: "hostName" }
      end

      if host_from_location.present?
        return host_decision(host_from_location, :page_location_host_match, "pageLocation") if ALLOWED_HOSTS.include?(host_from_location)
        return { accepted: false, reason: :wrong_host, resolved_host: host_from_location, match_source: "pageLocation" }
      end

      if page_path.present? && property_matches_suelog? && business&.id == expected_business_id && business_source_setting&.enabled? && setting&.enabled?
        return { accepted: true, reason: :property_business_setting_match_no_host, resolved_host: ALLOWED_HOSTS.first, match_source: "property_business_setting" }
      end

      { accepted: false, reason: :blank_host, resolved_host: nil, match_source: "none" }
    end

    def host_decision(host, reason, match_source = "hostName")
      { accepted: true, reason:, resolved_host: host, match_source: }
    end

    def diagnostic_row(index, row, host_decision)
      {
        row_index: index,
        hostName: row["hostName"],
        pagePath: row["pagePath"],
        pageLocation: row["pageLocation"],
        dimensionValues: row["dimensionValues"],
        normalized_host: normalize_host(row["hostName"]).presence || normalize_host(host_from_url(row["pageLocation"])),
        normalized_path: Aicoo::UrlNormalizer.call(row["pagePath"]),
        expected_hosts: ALLOWED_HOSTS,
        host_match_source: host_decision.fetch(:match_source),
        host_match_method: "hostName -> pageLocation host -> property/business/source-setting",
        accepted: host_decision.fetch(:accepted),
        exclude_reason: host_decision.fetch(:accepted) ? nil : host_decision.fetch(:reason),
        accepted_reason: host_decision.fetch(:accepted) ? host_decision.fetch(:reason) : nil
      }
    end

    def normalize_host(value)
      normalized = value.to_s.strip.downcase
      return nil if normalized.blank? || normalized == "(not set)"

      host_from_url(normalized).presence || normalized
    end

    def host_from_url(value)
      URI.parse(value.to_s).host
    rescue URI::InvalidURIError
      nil
    end
  end
end
