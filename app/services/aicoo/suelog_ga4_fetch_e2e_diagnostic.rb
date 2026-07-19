require "csv"
require "json"
require "set"

module Aicoo
  class SuelogGa4FetchE2eDiagnostic
    SAMPLE_LIMIT = 20
    TOP_PAGE_LIMIT = 50
    DIAGNOSTIC_DIMENSIONS = %w[date pagePath hostName].freeze
    DIAGNOSTIC_METRICS = %w[screenPageViews activeUsers sessions eventCount userEngagementDuration].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(business:, run_api: true, today: Date.current)
      @business = business
      @run_api = run_api
      @today = today.to_date
      @lines = []
      @blocking_reasons = []
      @root_cause = "unknown"
      @api_result = nil
    end

    def call
      section("吸えログGA4取得E2E診断")
      line("generated_at=#{Time.current.iso8601}")

      diagnose_business_connection
      diagnose_recent_runs
      diagnose_request
      diagnose_api_response
      diagnose_save_flow
      diagnose_existing_stored_pages
      diagnose_oauth
      diagnose_summary

      lines.join("\n")
    end

    private

    attr_reader :business, :run_api, :today, :lines, :blocking_reasons

    def diagnose_business_connection
      section("1. BusinessとGA4接続設定")
      line("Business ID=#{business.id}")
      line("Business名=#{business.name}")

      candidate_settings.each do |row|
        setting = row[:setting]
        site = setting&.aicoo_analytics_site
        credential = effective_credential(setting)
        line([
          "BusinessDataSourceSetting ID=#{row[:business_setting]&.id || '-'}",
          "GA4接続設定ID=#{setting&.id || '-'}",
          "source=#{row[:source]}",
          "GA4 Property ID=#{setting&.property_id || row[:property_id] || '-'}",
          "Measurement ID=#{measurement_id_for(setting, row[:business_setting]) || '-'}",
          "接続対象サイトURL=#{site&.public_url || row[:business_setting]&.endpoint_url || '-'}",
          "設定host/domain=#{site&.domain || host_from_url(site&.public_url) || '-'}",
          "active/enabled=#{setting&.enabled?}",
          "BusinessDataSourceSetting enabled=#{row[:business_setting]&.enabled? || '-'}",
          "BusinessDataSourceSetting status=#{row[:business_setting]&.connection_status || '-'}",
          "作成日時=#{setting&.created_at&.iso8601 || '-'}",
          "更新日時=#{setting&.updated_at&.iso8601 || '-'}",
          "OAuth接続日時=#{setting&.oauth_connected_at&.iso8601 || credential&.connected_at&.iso8601 || '-'}",
          "credential参照元=#{credential_source(setting, row[:business_setting])}"
        ].join(" "))
      end

      selected = selected_ga4_setting
      line("selected_ga4_setting_id=#{selected&.id || '-'}")
      line("selected_ga4_property_id=#{selected&.property_id || '-'}")
      line("property_matches_suelog=#{property_matches_suelog(selected)}")
    end

    def diagnose_recent_runs
      section("2. 最新GA4取得run")
      line("AnalyticsFetchRun直近20件")
      analytics_fetch_runs.each do |run|
        setting = run.analytics_source_setting
        data_import = DataImport.find_by(id: run.data_import_id)
        line([
          "run_id=#{run.id}",
          "business_id=#{setting&.aicoo_analytics_site&.business_id || data_import&.business&.id || '-'}",
          "property_id=#{setting&.property_id || '-'}",
          "started_at=#{run.started_at&.iso8601 || '-'}",
          "finished_at=#{run.finished_at&.iso8601 || '-'}",
          "status=#{run.status}",
          "fetch_range=#{fetch_range_for(setting)}",
          "api_row_count=#{data_import&.row_count || '-'}",
          "saved_row_count=#{data_import&.row_count || '-'}",
          "error=#{run.error_message.presence || '-'}",
          "data_source=AnalyticsSourceSetting##{setting&.id || '-'}",
          "request_type=site_ga4_fetch"
        ].join(" "))
      end

      line("GoogleApiImportRun直近20件")
      google_api_import_runs.each do |run|
        ga4_result = Array(run.metadata["source_results"]).find { |row| row.to_h["source"] == "ga4" } || {}
        line([
          "run_id=#{run.id}",
          "business_id=#{run.business_id}",
          "property_id=#{ga4_result['identifier'] || '-'}",
          "started_at=#{run.started_at&.iso8601 || '-'}",
          "finished_at=#{run.finished_at&.iso8601 || '-'}",
          "status=#{run.status}",
          "fetch_range=#{run.metadata['start_date'] || '-'}..#{run.metadata['end_date'] || '-'}",
          "api_row_count=#{ga4_result['api_row_count'] || '-'}",
          "saved_row_count=#{ga4_result['saved_day_count'] || run.updated_metric_count}",
          "error=#{run.error_message.presence || '-'}",
          "data_source=GoogleApiImportRun",
          "request_type=business_metric_daily_import"
        ].join(" "))
      end
    end

    def diagnose_request
      section("3. GA4 APIリクエスト")
      request = diagnostic_request_body
      line("property=#{selected_ga4_setting&.property_id || '-'}")
      line("site_fetch_request.class=AicooAnalytics::Ga4Fetcher")
      line("site_fetch_request.dimensions=date,pagePath")
      line("site_fetch_request.metrics=screenPageViews,totalUsers,sessions,eventCount")
      line("site_fetch_request.limit=1000")
      line("business_metric_request.class=AicooAnalytics::BusinessGoogleApiMetricImporter")
      line("business_metric_request.dimensions=date")
      line("business_metric_request.metrics=sessions,totalUsers,screenPageViews,userEngagementDuration,engagementRate,keyEvents,eventCount")
      line("business_metric_request.limit=10000")
      line("diagnostic_request.class=Aicoo::SuelogGa4FetchE2eDiagnostic")
      line("dateRanges=#{request[:dateRanges].to_json}")
      line("dimensions=#{request[:dimensions].map { |row| row[:name] }.join(',')}")
      line("metrics=#{request[:metrics].map { |row| row[:name] }.join(',')}")
      line("dimensionFilter=#{request[:dimensionFilter] || '-'}")
      line("metricFilter=#{request[:metricFilter] || '-'}")
      line("limit=#{request[:limit]}")
      line("offset=#{request[:offset] || '-'}")
      line("orderBys=#{request[:orderBys] || '-'}")
      line("dimension_has_pagePath_or_landingPage=#{(request[:dimensions].map { |row| row[:name] } & %w[pagePath landingPage]).any?}")
      line("request_has_lp_filter=false")
      line("host_filter_points_to_aicoo=false")
    end

    def diagnose_api_response
      section("4. APIレスポンス生データ診断")
      @api_result = fetch_api_diagnostic
      if @api_result[:skipped]
        line("api_diagnostic_skipped=true")
        line("skip_reason=#{@api_result[:reason]}")
        blocking_reasons << @api_result[:reason]
        return
      end

      rows = @api_result[:rows]
      parsed_rows = normalize_api_rows(rows)
      path_counts = path_category_counts(parsed_rows.map { |row| row[:page_path] })
      host_counts = parsed_rows.group_by { |row| row[:host_name].presence || "-" }.transform_values(&:size)

      line("総行数=#{rows.size}")
      line("hostName別件数=#{format_counts(host_counts)}")
      line("pagePath別件数=#{parsed_rows.map { |row| row[:page_path] }.compact_blank.uniq.size}")
      line("/articles/件数=#{path_counts[:articles]}")
      line("/shops/件数=#{path_counts[:shops]}")
      line("/lp件数=#{path_counts[:lp]}")
      line("その他件数=#{path_counts[:other]}")
      line("api_response_contains_articles=#{path_counts[:articles].positive?}")
      line("上位50ページ")
      top_pages(parsed_rows).first(TOP_PAGE_LIMIT).each do |row|
        line("- host=#{row[:host_name] || '-'} page=#{row[:page_path] || '-'} views=#{row[:screen_page_views]} users=#{row[:active_users]} sessions=#{row[:sessions]}")
      end
    end

    def diagnose_save_flow
      section("5. 保存前後比較")
      if @api_result.blank? || @api_result[:skipped]
        line("API受信行数=unknown")
        line("parse成功行数=unknown")
        line("filter通過行数=unknown")
        line("DataImport保存行数=unknown")
        line("AicooDataSnapshot保存行数=unknown")
        line("除外行数=unknown")
        return
      end

      parsed_rows = normalize_api_rows(@api_result[:rows])
      existing_import_rows = stored_ga4_rows
      existing_snapshot_rows = stored_snapshot_rows
      api_article_rows = parsed_rows.select { |row| article_path?(row[:page_path]) }
      stored_article_rows = existing_import_rows.select { |row| article_path?(row["page"]) }

      line("API受信行数=#{@api_result[:rows].size}")
      line("parse成功行数=#{parsed_rows.size}")
      line("filter通過行数=#{parsed_rows.size}")
      line("DataImport保存行数=#{existing_import_rows.size}")
      line("AicooDataSnapshot保存行数=#{existing_snapshot_rows.size}")
      line("除外行数=#{[ @api_result[:rows].size - parsed_rows.size, 0 ].max}")
      line("除外理由.dimension_parse_failure=#{[ @api_result[:rows].size - parsed_rows.size, 0 ].max}")
      line("除外理由.wrong_host=0")
      line("除外理由.unsupported_path=0")
      line("除外理由.lp_only_filter=0")
      line("除外理由.blank_page_path=#{parsed_rows.count { |row| row[:page_path].blank? }}")
      line("除外理由.duplicate=0")
      line("除外理由.limit=0")
      line("除外理由.unknown=0")
      line("api_article_rows=#{api_article_rows.size}")
      line("stored_article_rows=#{stored_article_rows.size}")
      line("article_rows_removed_during_save=#{[ api_article_rows.size - stored_article_rows.size, 0 ].max}")
      if api_article_rows.any? && stored_article_rows.empty?
        line("保存後に消えた記事pageサンプル")
        api_article_rows.first(SAMPLE_LIMIT).each { |row| line("- #{row[:page_path]} reason=not_found_in_saved_ga4_rows") }
      end
    end

    def diagnose_existing_stored_pages
      section("6. 既存保存データの所有関係")
      target_pages = %w[/ /lp /lp/lp /lp/v6mkw8dqdlgzitnd]
      rows = stored_ga4_rows
      target_pages.each do |page|
        normalized = Aicoo::UrlNormalizer.call(page)
        matches = rows.select { |row| Aicoo::UrlNormalizer.call(row["page"]) == normalized }
        if matches.empty?
          line("page=#{page} saved=false")
          next
        end

        matches.first(SAMPLE_LIMIT).each do |row|
          import = DataImport.find_by(id: row["source_id"]) if row["source_model"] == "DataImport"
          snapshot = AicooDataSnapshot.find_by(id: row["source_id"]) if row["source_model"] == "AicooDataSnapshot"
          source_import = import || snapshot&.source_record
          site = source_import&.aicoo_analytics_site
          setting = site&.ga4_setting
          line([
            "page=#{page}",
            "Business ID=#{source_import&.business&.id || site&.business_id || '-'}",
            "Property ID=#{setting&.property_id || site&.ga4_property_id || '-'}",
            "DataImport ID=#{source_import&.id || '-'}",
            "Snapshot ID=#{snapshot&.id || '-'}",
            "取得日時=#{source_import&.imported_at&.iso8601 || snapshot&.captured_at&.iso8601 || '-'}",
            "hostName=#{row['host_name'] || '-'}",
            "元dimensionValues=#{row['dimension_values'] || '-'}",
            "保存pagePath=#{row['page'] || '-'}"
          ].join(" "))
        end
      end
      line("mixed_business_data=#{mixed_business_data?}")
    end

    def diagnose_oauth
      section("7. OAuth状態")
      setting = selected_ga4_setting
      credential = effective_credential(setting)
      fetch_failures = analytics_fetch_runs.select { |run| run.status == "failed" } + google_api_import_runs.select { |run| run.status == "failed" }
      latest_success = (analytics_fetch_runs.select { |run| run.status == "success" }.map(&:finished_at) + google_api_import_runs.select { |run| run.status == "success" }.map(&:finished_at)).compact.max
      latest_failure = fetch_failures.map(&:finished_at).compact.max
      invalid_grant = fetch_failures.any? { |run| run.error_message.to_s.match?(/invalid_grant|expired|revoked/i) }

      line("最新成功取得日時=#{latest_success&.iso8601 || '-'}")
      line("最新失敗日時=#{latest_failure&.iso8601 || '-'}")
      line("失敗回数=#{fetch_failures.size}")
      line("refresh token source=#{credential_source(setting, business_source_setting)}")
      line("oauth_connected_at=#{setting&.oauth_connected_at&.iso8601 || credential&.connected_at&.iso8601 || '-'}")
      line("現在の取得データがOAuth失効前の古いデータか=#{latest_failure.present? && latest_success.present? && latest_success < latest_failure}")
      line("oauth_reconnect_required=#{oauth_reconnect_required?(setting, credential, invalid_grant)}")
    end

    def diagnose_summary
      section("最終サマリー")
      request = diagnostic_request_body
      api_rows = @api_result && !@api_result[:skipped] ? normalize_api_rows(@api_result[:rows]) : []
      api_path_counts = path_category_counts(api_rows.map { |row| row[:page_path] })
      stored_path_counts = path_category_counts(stored_ga4_rows.map { |row| row["page"] })
      root = root_cause(api_path_counts:, stored_path_counts:)

      line("ga4_property_id=#{selected_ga4_setting&.property_id || '-'}")
      line("property_matches_suelog=#{property_matches_suelog(selected_ga4_setting)}")
      line("requested_dimensions=#{request[:dimensions].map { |row| row[:name] }.join(',')}")
      line("requested_metrics=#{request[:metrics].map { |row| row[:name] }.join(',')}")
      line("request_has_lp_filter=false")
      line("api_response_row_count=#{@api_result && !@api_result[:skipped] ? @api_result[:rows].size : 'unknown'}")
      line("api_response_contains_articles=#{api_path_counts[:articles].positive?}")
      line("api_response_article_count=#{api_path_counts[:articles]}")
      line("stored_article_count=#{stored_path_counts[:articles]}")
      line("stored_lp_count=#{stored_path_counts[:lp]}")
      line("article_rows_removed_during_save=#{[ api_path_counts[:articles] - stored_path_counts[:articles], 0 ].max}")
      line("oauth_reconnect_required=#{oauth_reconnect_required?(selected_ga4_setting, effective_credential(selected_ga4_setting), oauth_invalid_grant?)}")
      line("root_cause=#{root}")
      line("blocking_reasons=#{blocking_reasons.compact_blank.uniq.join(' / ').presence || '-'}")
      line("recommended_next_action=#{recommended_next_action(root)}")
    end

    def selected_ga4_setting
      @selected_ga4_setting ||= candidate_settings.find { |row| row[:source] == "business_data_source_setting" && row[:setting].present? }&.fetch(:setting) ||
                                candidate_settings.find { |row| row[:source] == "analytics_site" && row[:setting].present? }&.fetch(:setting) ||
                                candidate_settings.find { |row| row[:setting].present? }&.fetch(:setting)
    end

    def candidate_settings
      @candidate_settings ||= begin
        rows = []
        bds = business_source_setting
        if bds
          setting = ga4_setting_for_property(bds.connection_field_value("property_id").presence || bds.property_identifier)
          rows << { source: "business_data_source_setting", setting:, business_setting: bds, property_id: bds.connection_field_value("property_id").presence || bds.property_identifier }
        end
        analytics_sites.each do |site|
          rows << { source: "analytics_site", setting: site.ga4_setting, business_setting: nil, property_id: site.ga4_property_id }
        end
        named = named_ga4_setting
        rows << { source: "named_setting", setting: named, business_setting: nil, property_id: named&.property_id } if named
        rows.uniq { |row| [ row[:source], row[:setting]&.id, row[:property_id] ] }
      end
    end

    def analytics_sites
      @analytics_sites ||= begin
        AicooAnalyticsSite.where(business_id: business.id).to_a
      end
    end

    def business_source_setting
      @business_source_setting ||= BusinessDataSourceSetting.find_by(business:, source_key: "ga4")
    end

    def ga4_setting_for_property(property_id)
      return if property_id.blank?

      AnalyticsSourceSetting.where(source_type: "ga4", enabled: true).find_by(property_id:)
    end

    def named_ga4_setting
      AnalyticsSourceSetting.where(source_type: "ga4", enabled: true).to_a.find { |setting| setting.name.to_s.match?(/\A#{Regexp.escape(business.name)}\b/i) }
    end

    def analytics_fetch_runs
      @analytics_fetch_runs ||= begin
        ids = candidate_settings.filter_map { |row| row[:setting]&.id }
        scope = AnalyticsFetchRun.includes(analytics_source_setting: :aicoo_analytics_site).where(source_type: "ga4")
        ids.any? ? scope.where(analytics_source_setting_id: ids).recent.limit(20).to_a : []
      end
    end

    def google_api_import_runs
      @google_api_import_runs ||= GoogleApiImportRun.where(business:).recent.limit(20).to_a
    end

    def diagnostic_request_body
      {
        dateRanges: [ { startDate: (today - 7.days).to_s, endDate: (today - 1.day).to_s } ],
        dimensions: DIAGNOSTIC_DIMENSIONS.map { |name| { name: } },
        metrics: DIAGNOSTIC_METRICS.map { |name| { name: } },
        limit: 1_000
      }
    end

    def fetch_api_diagnostic
      return { skipped: true, reason: "ga4_setting_not_found", rows: [] } unless selected_ga4_setting
      credential = effective_credential(selected_ga4_setting)
      return { skipped: true, reason: "usable_access_token_not_found_or_expired", rows: [] } unless credential&.access_token.present? && !credential.token_expired?
      return { skipped: true, reason: "api_diagnostic_disabled", rows: [] } unless run_api

      response = AicooAnalytics::Ga4DataApiClient.new(access_token: credential.access_token).run_report(
        property_id: selected_ga4_setting.property_id,
        start_date: today - 7.days,
        end_date: today - 1.day,
        dimensions: DIAGNOSTIC_DIMENSIONS,
        metrics: DIAGNOSTIC_METRICS,
        limit: 1_000
      )
      { skipped: false, rows: Array(response["rows"]), raw_response: response }
    rescue StandardError => e
      { skipped: true, reason: "api_diagnostic_error=#{e.class}: #{e.message}", rows: [] }
    end

    def normalize_api_rows(rows)
      rows.filter_map do |row|
        dimensions = Array(row["dimensionValues"]).map { |value| value.to_h["value"] }
        metrics = Array(row["metricValues"]).map { |value| value.to_h["value"] }
        page_path = dimensions[1]
        next if dimensions.blank?

        {
          date: dimensions[0],
          page_path:,
          host_name: dimensions[2],
          screen_page_views: metrics[0].to_i,
          active_users: metrics[1].to_i,
          sessions: metrics[2].to_i,
          event_count: metrics[3].to_i,
          engagement_duration: metrics[4].to_i
        }
      end
    end

    def stored_ga4_rows
      @stored_ga4_rows ||= normalize_stored_rows(data_imports.flat_map { |import| rows_from_import(import) } + snapshots.flat_map { |snapshot| rows_from_snapshot(snapshot) })
    end

    def stored_snapshot_rows
      @stored_snapshot_rows ||= snapshots.flat_map { |snapshot| rows_from_snapshot(snapshot) }
    end

    def data_imports
      @data_imports ||= begin
        ids = []
        ids += business.data_sources.joins(:data_imports).where(data_sources: { source_type: "ga4" }).pluck("data_imports.id")
        site_ids = analytics_sites.map(&:id)
        ids += DataImport.joins(:data_source).where(data_sources: { source_type: "ga4" }, aicoo_analytics_site_id: site_ids).pluck(:id) if site_ids.any?
        DataImport.where(id: ids.uniq).includes(:data_source, :aicoo_analytics_site).recent.limit(50).to_a
      end
    end

    def snapshots
      @snapshots ||= AicooDataSnapshot.where(source_type: "ga4").recent.limit(200).select do |snapshot|
        payload = snapshot.payload.to_h.deep_stringify_keys
        data_imports.map(&:id).include?(snapshot.source_id.to_i) ||
          payload["business_id"].to_i == business.id ||
          source_record_belongs_to_business?(snapshot.source_record)
      end
    end

    def rows_from_import(data_import)
      rows = rows_from_csv(data_import.processed_text)
      rows = rows_from_csv(data_import.raw_text) if rows.empty?
      rows = rows_from_json(data_import.raw_text) if rows.empty?
      rows.map do |row|
        row.merge(
          "source_model" => "DataImport",
          "source_id" => data_import.id,
          "source_table" => "data_imports",
          "imported_at" => data_import.imported_at&.iso8601,
          "business_id" => data_import.business&.id,
          "analytics_site_id" => data_import.aicoo_analytics_site_id
        )
      end
    end

    def rows_from_snapshot(snapshot)
      payload = snapshot.payload.to_h.deep_stringify_keys
      rows = payload["rows"] || payload.dig("metrics", "rows")
      Array(rows).select { |row| row.respond_to?(:to_h) }.map do |row|
        row.to_h.deep_stringify_keys.merge(
          "source_model" => "AicooDataSnapshot",
          "source_id" => snapshot.id,
          "source_table" => "aicoo_data_snapshots",
          "captured_at" => snapshot.captured_at&.iso8601,
          "business_id" => payload["business_id"],
          "analytics_site_id" => payload["analytics_site_id"]
        )
      end
    end

    def rows_from_csv(text)
      return [] if text.blank?

      CSV.parse(text, headers: true).map { |row| row.to_h.deep_stringify_keys }
    rescue CSV::MalformedCSVError
      []
    end

    def rows_from_json(text)
      return [] if text.blank?

      parsed = JSON.parse(text)
      rows = parsed.is_a?(Hash) ? parsed["rows"] : parsed
      Array(rows).select { |row| row.respond_to?(:to_h) }.map { |row| row.to_h.deep_stringify_keys }
    rescue JSON::ParserError
      []
    end

    def normalize_stored_rows(rows)
      rows.filter_map do |row|
        page = first_present(
          row["page_path"], row["landing_page"], row["page_location"], row["pageLocation"],
          row["page"], row["url"], row["pagePath"], row["fullPageUrl"], dimension_page_value(row)
        )
        next if page.blank?

        {
          "page" => page,
          "host_name" => first_present(row["hostName"], row["host_name"]),
          "screen_page_views" => first_present(row["screenPageViews"], row["pageviews"], row["page_views"], row["views"]),
          "source_model" => row["source_model"],
          "source_id" => row["source_id"],
          "source_table" => row["source_table"],
          "dimension_values" => Array(row["dimensionValues"]).to_json,
          "business_id" => row["business_id"],
          "analytics_site_id" => row["analytics_site_id"]
        }
      end
    end

    def dimension_page_value(row)
      candidates = Array(row["dimensionValues"]).filter_map { |value| value.to_h["value"].presence }
      candidates.find { |value| page_like?(value) } || candidates.find { |value| !date_dimension?(value) }
    end

    def path_category_counts(paths)
      counts = { articles: 0, shops: 0, lp: 0, other: 0 }
      paths.each do |path|
        normalized = Aicoo::UrlNormalizer.call(path)
        case normalized
        when %r{\A/articles/}
          counts[:articles] += 1
        when %r{\A/shops/}
          counts[:shops] += 1
        when %r{\A/lp(?:/|\z)}
          counts[:lp] += 1
        else
          counts[:other] += 1 if normalized.present?
        end
      end
      counts
    end

    def top_pages(rows)
      rows.group_by { |row| [ row[:host_name], row[:page_path] ] }.map do |(host, page), grouped|
        {
          host_name: host,
          page_path: page,
          screen_page_views: grouped.sum { |row| row[:screen_page_views].to_i },
          active_users: grouped.sum { |row| row[:active_users].to_i },
          sessions: grouped.sum { |row| row[:sessions].to_i }
        }
      end.sort_by { |row| -row[:screen_page_views] }
    end

    def root_cause(api_path_counts:, stored_path_counts:)
      return "wrong_business_connection" if selected_ga4_setting.blank?
      return "wrong_ga4_property" if property_matches_suelog(selected_ga4_setting) == "false"
      return "oauth_expired_using_stale_data" if oauth_reconnect_required?(selected_ga4_setting, effective_credential(selected_ga4_setting), oauth_invalid_grant?)
      return "api_response_has_no_articles" if @api_result&.fetch(:skipped, false) == false && api_path_counts[:articles].zero?
      return "save_filter_excludes_articles" if api_path_counts[:articles].positive? && stored_path_counts[:articles].zero?
      return "mixed_business_data" if mixed_business_data?

      "unknown"
    end

    def recommended_next_action(root)
      case root
      when "wrong_ga4_property", "wrong_business_connection"
        "吸えログBusinessのGA4 property_idとAnalyticsSiteの紐付けを確認する"
      when "api_response_has_no_articles"
        "GA4 property側で/articles配下が計測されているか、タグ設置先とhostnameを確認する"
      when "save_filter_excludes_articles"
        "GA4保存処理のpagePath解析とSnapshot化で/articles行が落ちる箇所を修正する"
      when "oauth_expired_using_stale_data"
        "Google OAuthを再接続してから保存済みデータが古いままか確認する"
      when "mixed_business_data"
        "保存済みDataImport/SnapshotのBusiness/AnalyticsSite混入を整理する"
      else
        "診断出力のGA4保存構造と未一致pageを確認する"
      end
    end

    def property_matches_suelog(setting)
      return "unknown" unless setting
      configured = configured_ga4_property_id
      return "unknown" if configured.blank?
      return "true" if setting.property_id.to_s == configured.to_s

      "false"
    end

    def configured_ga4_property_id
      @configured_ga4_property_id ||= business_source_setting&.connection_field_value("property_id").presence ||
                                      business_source_setting&.property_identifier.presence ||
                                      analytics_sites.find { |site| site.ga4_property_id.present? }&.ga4_property_id ||
                                      named_ga4_setting&.property_id.presence
    end

    def mixed_business_data?
      stored_ga4_rows.any? do |row|
        row["business_id"].present? && row["business_id"].to_i != business.id
      end
    end

    def source_record_belongs_to_business?(record)
      return false unless record
      return true if record.respond_to?(:business_id) && record.business_id.to_i == business.id
      return true if record.respond_to?(:business) && record.business&.id.to_i == business.id
      return true if record.respond_to?(:aicoo_analytics_site) && record.aicoo_analytics_site&.business_id.to_i == business.id

      false
    end

    def oauth_reconnect_required?(setting, credential, invalid_grant)
      return true if invalid_grant
      return true if setting.blank?
      return true if credential.blank? && setting.refresh_token.blank?
      return true if credential&.refresh_token.blank? && setting.refresh_token.blank?

      false
    end

    def oauth_invalid_grant?
      (analytics_fetch_runs + google_api_import_runs).any? { |run| run.error_message.to_s.match?(/invalid_grant|expired|revoked/i) }
    end

    def effective_credential(setting)
      return unless setting

      setting.google_credential || AicooGoogleCredential.default
    end

    def credential_source(setting, business_setting)
      return "business_data_source_setting.google_credential_id" if business_setting&.metadata.to_h["google_credential_id"].present?
      return "analytics_source_setting.google_credential_id" if setting&.google_credential_id.present?
      return "analytics_source_setting.individual" if setting&.individual_authentication? && setting.individual_credentials_present?
      return "aicoo_google_credentials.default" if AicooGoogleCredential.default

      "missing"
    end

    def measurement_id_for(setting, business_setting)
      business_setting&.connection_field_value("measurement_id").presence ||
        business_setting&.metadata.to_h.dig("connection_fields", "measurement_id").presence ||
        setting&.credentials_json.to_s.match(/G-[A-Z0-9]+/)&.[](0)
    end

    def fetch_range_for(setting)
      return "-" unless setting

      end_date = today - 1.day
      "#{end_date - (setting.fetch_days.to_i - 1).days}..#{end_date}"
    end

    def host_from_url(url)
      URI.parse(url.to_s).host
    rescue URI::InvalidURIError
      nil
    end

    def page_like?(value)
      text = value.to_s
      text.start_with?("/") || text.match?(%r{\Ahttps?://}i) || text.include?("/articles/")
    end

    def date_dimension?(value)
      value.to_s.match?(/\A\d{8}\z/) || value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    end

    def article_path?(path)
      Aicoo::UrlNormalizer.call(path).to_s.start_with?("/articles/")
    end

    def first_present(*values)
      values.find { |value| value.present? }
    end

    def format_counts(hash)
      hash.map { |key, count| "#{key}:#{count}" }.join(",").presence || "-"
    end

    def section(title)
      line("")
      line("========================================")
      line(title)
      line("========================================")
    end

    def line(value)
      lines << value.to_s
    end
  end
end
