require "csv"
require "digest"
require "json"
require "set"
require "uri"

module Aicoo
  class ArticleAnalyticsSnapshotBuilder
    SOURCE_TYPE = "article_analytics"
    CLICK_TYPES = %w[phone map affiliate article_shop].freeze
    ARTICLE_URL_COLUMNS = %w[url canonical_url public_url source_url path page_path].freeze
    SHOP_CLICK_URL_COLUMNS = %w[source_url source_article_url article_url page_path path url referrer_url].freeze

    Result = Data.define(
      :mode,
      :business,
      :published_article_count,
      :snapshot_count,
      :created_count,
      :updated_count,
      :gsc_joined_count,
      :ga4_joined_count,
      :shop_click_joined_count,
      :three_source_joined_count,
      :missing_articles,
      :failed_count,
      :snapshot_ids,
      :gsc_duplicate_candidates,
      :ga4_duplicate_candidates,
      :article_info_rates,
      :unavailable_counts,
      :sample_payloads,
      :gsc_snapshot_quality,
      :ga4_snapshot_quality,
      :article_content_diagnostics
    )

    Snapshot = Data.define(:article, :payload)

    def self.call(...)
      new(...).call
    end

    def initialize(business: default_business, apply: false, captured_at: Time.current)
      @business = business
      @apply = ActiveModel::Type::Boolean.new.cast(apply)
      @captured_at = captured_at
      @created_count = 0
      @updated_count = 0
      @failed_count = 0
      @snapshot_ids = []
    end

    def call
      snapshots = build_snapshots
      persist_snapshots!(snapshots) if apply
      build_result(snapshots)
    end

    def build_snapshots
      return [] unless suelog_available?

      articles.map do |article|
        Snapshot.new(article:, payload: payload_for(article))
      rescue StandardError
        @failed_count += 1
        nil
      end.compact
    end

    def diagnostic_result
      snapshots = latest_persisted_snapshots
      article_paths = articles.index_by { |article| normalized_article_path(article) }
      payloads = snapshots.map { |snapshot| snapshot.payload.to_h.deep_stringify_keys }
      missing = missing_articles_for(payloads, article_paths)

      Result.new(
        mode: "diagnose",
        business:,
        published_article_count: articles.size,
        snapshot_count: payloads.size,
        created_count: 0,
        updated_count: 0,
        gsc_joined_count: payloads.count { |payload| joined?(payload, "gsc", "impressions", "clicks") },
        ga4_joined_count: payloads.count { |payload| joined?(payload, "ga4", "pageviews", "active_users", "sessions") },
        shop_click_joined_count: payloads.count { |payload| joined?(payload, "shop_click", "total_clicks") },
        three_source_joined_count: payloads.count { |payload| joined?(payload, "gsc", "impressions", "clicks") && joined?(payload, "ga4", "pageviews", "active_users", "sessions") && joined?(payload, "shop_click", "total_clicks") },
        missing_articles: missing,
        failed_count: 0,
        snapshot_ids: snapshots.map(&:id),
        gsc_duplicate_candidates: gsc_duplicate_candidates,
        ga4_duplicate_candidates: ga4_duplicate_candidates,
        article_info_rates: article_info_rates(payloads),
        unavailable_counts: unavailable_counts(payloads),
        sample_payloads: payloads.first(5),
        gsc_snapshot_quality: snapshot_quality_for("gsc"),
        ga4_snapshot_quality: snapshot_quality_for("ga4"),
        article_content_diagnostics: article_content_diagnostics(payloads)
      )
    end

    private

    attr_reader :business, :apply, :captured_at

    def default_business
      Business.kept.find_by(name: "吸えログ") ||
        Business.kept.find { |row| suelog_business?(row) }
    end

    def suelog_business?(row)
      metadata = row.metadata.to_h
      [
        row.name,
        row.try(:project_key),
        row.try(:repository_name),
        row.try(:local_project_path),
        row.try(:source),
        row.try(:gsc_site_url),
        metadata["source_app"],
        metadata["source_system"],
        metadata["business_key"],
        metadata["slug"],
        metadata["project_key"]
      ].compact.any? { |value| value.to_s.match?(/吸えログ|suelog|sue-log/i) }
    end

    def suelog_available?
      return false if business.blank?
      return @suelog_available if defined?(@suelog_available)

      SuelogRecord.ensure_connection!
      @suelog_available = defined?(::Suelog::Article)
    rescue StandardError
      @suelog_available = false
    end

    def articles
      @articles ||= begin
        return [] unless suelog_available?

        scope = ::Suelog::Article.all
        scope = scope.where(published: true) if column?(::Suelog::Article, "published")
        scope = scope.where("published_at IS NULL OR published_at <= ?", Time.current) if column?(::Suelog::Article, "published_at")
        scope.order(order_column(::Suelog::Article) => :desc).to_a
      end
    end

    def payload_for(article)
      normalized_path = normalized_article_path(article)
      gsc = gsc_by_path.fetch(normalized_path, empty_gsc)
      ga4 = ga4_by_path.fetch(normalized_path, empty_ga4)
      shop_click = shop_click_by_article_id.fetch(article.id, empty_shop_click)

      {
        "source_type" => SOURCE_TYPE,
        "business_id" => business.id,
        "business_name" => business.name,
        "article_id" => article.id,
        "article_url" => article_canonical_url(article) || article_path(article),
        "normalized_path" => normalized_path,
        "slug" => safe_attr(article, "slug"),
        "gsc" => gsc,
        "ga4" => ga4,
        "shop_click" => shop_click,
        "article" => article_payload(article),
        "business_metric" => business_metric_payload,
        "learning" => learning_payload(article, normalized_path),
        "snapshot_generated_at" => captured_at.iso8601
      }
    end

    def persist_snapshots!(snapshots)
      snapshots.each do |snapshot|
        record = AicooDataSnapshot
          .where(source_type: SOURCE_TYPE, source_id: snapshot.article.id, captured_at: captured_at.all_day)
          .first

        if record
          record.update!(payload: snapshot.payload, captured_at:)
          @updated_count += 1
        else
          record = AicooDataSnapshot.create!(
            source_type: SOURCE_TYPE,
            source_id: snapshot.article.id,
            captured_at:,
            payload: snapshot.payload
          )
          @created_count += 1
        end
        @snapshot_ids << record.id
      rescue StandardError
        @failed_count += 1
      end
    end

    def build_result(snapshots)
      payloads = snapshots.map(&:payload)
      Result.new(
        mode: apply ? "apply" : "dry-run",
        business:,
        published_article_count: articles.size,
        snapshot_count: snapshots.size,
        created_count: @created_count,
        updated_count: @updated_count,
        gsc_joined_count: payloads.count { |payload| joined?(payload, "gsc", "impressions", "clicks") },
        ga4_joined_count: payloads.count { |payload| joined?(payload, "ga4", "pageviews", "active_users", "sessions") },
        shop_click_joined_count: payloads.count { |payload| joined?(payload, "shop_click", "total_clicks") },
        three_source_joined_count: payloads.count { |payload| joined?(payload, "gsc", "impressions", "clicks") && joined?(payload, "ga4", "pageviews", "active_users", "sessions") && joined?(payload, "shop_click", "total_clicks") },
        missing_articles: missing_articles_for(payloads, articles.index_by { |article| normalized_article_path(article) }),
        failed_count: @failed_count,
        snapshot_ids: @snapshot_ids,
        gsc_duplicate_candidates: gsc_duplicate_candidates,
        ga4_duplicate_candidates: ga4_duplicate_candidates,
        article_info_rates: article_info_rates(payloads),
        unavailable_counts: unavailable_counts(payloads),
        sample_payloads: payloads.first(5),
        gsc_snapshot_quality: snapshot_quality_for("gsc"),
        ga4_snapshot_quality: snapshot_quality_for("ga4"),
        article_content_diagnostics: article_content_diagnostics(payloads)
      )
    end

    def latest_persisted_snapshots
      ids = articles.map(&:id)
      return [] if ids.empty?

      AicooDataSnapshot
        .where(source_type: SOURCE_TYPE, source_id: ids)
        .recent
        .to_a
        .uniq(&:source_id)
    end

    def joined?(payload, section, *fields)
      payload.dig(section, "available") == true
    end

    def gsc_duplicate_candidates
      duplicate_candidates_for(gsc_rows, :gsc)
    end

    def ga4_duplicate_candidates
      duplicate_candidates_for(ga4_rows, :ga4)
    end

    def duplicate_candidates_for(rows, source_type)
      rows
        .group_by { |row| metric_row_key(row, source_type) }
        .select { |_key, grouped| grouped.size > 1 }
        .first(20)
        .map do |_key, grouped|
          row = grouped.first
          {
            "page" => row["page"],
            "normalized_path" => normalize_url(row["page"]),
            "query" => row["query"],
            "date" => row["date"],
            "duplicate_count" => grouped.size,
            "source_models" => grouped.map { |item| item["source_model"] }.compact.uniq,
            "source_ids" => grouped.map { |item| item["source_id"] }.compact.uniq
          }
        end
    end

    def article_info_rates(payloads)
      total = payloads.size
      return {} if total.zero?

      %w[shop_count verified_shop_count word_count internal_link_count].index_with do |field|
        present = payloads.count { |payload| !payload.dig("article", field).nil? }
        {
          "present" => present,
          "total" => total,
          "rate" => ((present.to_d / total) * 100).round(1).to_f
        }
      end
    end

    def unavailable_counts(payloads)
      %w[gsc ga4 shop_click].index_with do |source|
        payloads.count { |payload| payload.dig(source, "available") != true }
      end
    end

    def snapshot_quality_for(source_type)
      total_snapshots = metric_snapshots_for(source_type, include_inactive: true)
      source_snapshots = total_snapshots.reject { |snapshot| inactive_metric_snapshot?(snapshot) }
      archived_snapshots = total_snapshots.select { |snapshot| snapshot_status(snapshot) == "archived" }
      ignored_snapshots = total_snapshots.select { |snapshot| snapshot_status(snapshot) == "ignored" }
      fingerprint_groups = source_snapshots.group_by { |snapshot| snapshot.payload.to_h["snapshot_fingerprint"].presence || legacy_snapshot_fingerprint(snapshot) }
      duplicate_groups = fingerprint_groups.values.select { |grouped| grouped.size > 1 }
      {
        "total_snapshot_count" => total_snapshots.size,
        "active_snapshot_count" => source_snapshots.size,
        "archived_snapshot_count" => archived_snapshots.size,
        "ignored_snapshot_count" => ignored_snapshots.size,
        "snapshot_count" => source_snapshots.size,
        "duplicate_snapshot_count" => duplicate_groups.sum { |grouped| grouped.size },
        "duplicate_group_count" => duplicate_groups.size,
        "duplicate_rate" => source_snapshots.any? ? ((duplicate_groups.sum(&:size).to_d / source_snapshots.size) * 100).round(1).to_f : 0,
        "duplicate_sources" => duplicate_groups.first(20).map do |grouped|
          {
            "snapshot_ids" => grouped.map(&:id),
            "source_ids" => grouped.map(&:source_id),
            "source_models" => grouped.map { |snapshot| snapshot.payload.to_h["source_model"].presence || "AicooDataSnapshot" }.uniq,
            "data_import_ids" => grouped.map { |snapshot| snapshot.payload.to_h["data_import_id"] }.compact.uniq,
            "imported_at" => grouped.map { |snapshot| snapshot.payload.to_h["imported_at"] }.compact.uniq
          }
        end
      }
    end

    def article_content_diagnostics(payloads)
      total = payloads.size
      source_counts = payloads.filter_map { |payload| payload.dig("article", "content_source") }.tally
      present_content = payloads.count { |payload| payload.dig("article", "content_source").present? && !payload.dig("article", "word_count").nil? }
      internal_links = payloads.count { |payload| !payload.dig("article", "internal_link_count").nil? }
      {
        "article_columns" => suelog_available? ? ::Suelog::Article.column_names : [],
        "article_associations" => suelog_available? ? ::Suelog::Article.reflect_on_all_associations.map(&:name).map(&:to_s) : [],
        "content_tables" => content_table_candidates,
        "content_source_counts" => source_counts,
        "content_present_count" => present_content,
        "internal_link_present_count" => internal_links,
        "content_present_rate" => total.positive? ? ((present_content.to_d / total) * 100).round(1).to_f : 0.0,
        "internal_link_present_rate" => total.positive? ? ((internal_links.to_d / total) * 100).round(1).to_f : 0.0,
        "missing_content_articles" => payloads.filter_map do |payload|
          next if payload.dig("article", "content_source").present?

          {
            "article_id" => payload["article_id"],
            "path" => payload["normalized_path"],
            "title" => payload.dig("article", "title")
          }
        end
      }
    end

    def legacy_snapshot_fingerprint(snapshot)
      payload = snapshot.payload.to_h.deep_stringify_keys
      Digest::SHA256.hexdigest(JSON.generate(
        "source_type" => payload["source_type"],
        "business_id" => payload["business_id"],
        "analytics_site_id" => payload["analytics_site_id"],
        "domain" => payload["domain"],
        "rows" => Array(payload["rows"]).map { |row| row.to_h.deep_stringify_keys.sort.to_h }.sort_by(&:to_json)
      ))
    end

    def missing_articles_for(payloads, article_paths)
      payload_by_path = payloads.index_by { |payload| payload["normalized_path"] }
      article_paths.filter_map do |path, article|
        payload = payload_by_path[path]
        missing = []
        missing << "snapshot" if payload.blank?
        missing << "gsc" if payload && !joined?(payload, "gsc", "impressions", "clicks")
        missing << "ga4" if payload && !joined?(payload, "ga4", "pageviews", "active_users", "sessions")
        missing << "shop_click" if payload && !joined?(payload, "shop_click", "total_clicks")
        next if missing.empty?

        {
          "article_id" => article.id,
          "path" => path,
          "title" => safe_attr(article, "title"),
          "missing" => missing
        }
      end
    end

    def gsc_by_path
      @gsc_by_path ||= aggregate_gsc_rows(gsc_rows)
    end

    def ga4_by_path
      @ga4_by_path ||= aggregate_ga4_rows(ga4_rows)
    end

    def shop_click_by_article_id
      @shop_click_by_article_id ||= aggregate_shop_clicks
    end

    def aggregate_gsc_rows(rows)
      deduped_rows = deduplicate_metric_rows(rows, :gsc)
      deduped_rows.group_by { |row| normalize_url(row["page"]) }.transform_values do |grouped|
        totals = grouped
          .group_by { |row| row["date"].to_s.presence || "unknown_date" }
          .values
          .map { |date_rows| gsc_total_row_for_date(date_rows) }
        impressions = totals.sum { |row| decimal(row["impressions"]) }
        clicks = totals.sum { |row| decimal(row["clicks"]) }
        positions = totals.filter_map { |row| decimal(row["position"]).presence }
        query_rows = grouped.select { |row| row["query"].present? }
        queries = query_rows.group_by { |row| row["query"].to_s }.filter_map do |query, rows_for_query|
          next if query.blank?

          {
            "query" => query,
            "impressions" => rows_for_query.sum { |row| decimal(row["impressions"]) }.to_i,
            "clicks" => rows_for_query.sum { |row| decimal(row["clicks"]) }.to_i,
            "average_position" => average(rows_for_query.map { |row| decimal(row["position"]) }).to_f.round(2)
          }
        end.sort_by { |row| [ -row["impressions"], -row["clicks"] ] }.first(10)

        {
          "available" => true,
          "impressions" => impressions.to_i,
          "clicks" => clicks.to_i,
          "ctr" => impressions.positive? ? (clicks / impressions).to_f.round(4) : 0,
          "average_position" => average(positions).to_f.round(2),
          "query_count" => queries.size,
          "top_queries" => queries,
          "aggregation_method" => "deduped_page_daily_totals",
          "source_row_count" => grouped.size,
          "deduped_total_row_count" => totals.size
        }
      end
    end

    def aggregate_ga4_rows(rows)
      deduped_rows = deduplicate_metric_rows(rows, :ga4)
      deduped_rows.group_by { |row| normalize_url(row["page"]) }.transform_values do |grouped|
        dates = grouped.filter_map { |row| parse_date(row["date"]) }
        {
          "available" => true,
          "pageviews" => grouped.sum { |row| decimal(row["pageviews"]) }.to_i,
          "active_users" => grouped.sum { |row| decimal(row["active_users"]) }.to_i,
          "sessions" => grouped.sum { |row| decimal(row["sessions"]) }.to_i,
          "engagement_seconds" => grouped.sum { |row| decimal(row["engagement_seconds"]) }.to_i,
          "event_count" => grouped.sum { |row| decimal(row["event_count"]) }.to_i,
          "landing_page_views" => grouped.sum { |row| decimal(row["landing_page_views"]) }.to_i,
          "page_path" => grouped.first["page"],
          "first_seen" => dates.min&.iso8601,
          "last_seen" => dates.max&.iso8601,
          "aggregation_method" => "deduped_daily_page_rows",
          "source_row_count" => grouped.size
        }
      end
    end

    def gsc_total_row_for_date(rows)
      page_only_rows = rows.select { |row| row["query"].blank? }
      if page_only_rows.any?
        return page_only_rows.max_by { |row| row["source_priority"].to_i }
      end

      {
        "impressions" => rows.sum { |row| decimal(row["impressions"]) },
        "clicks" => rows.sum { |row| decimal(row["clicks"]) },
        "position" => average(rows.map { |row| decimal(row["position"]) })
      }
    end

    def deduplicate_metric_rows(rows, source_type)
      rows
        .group_by { |row| metric_row_key(row, source_type) }
        .values
        .map { |duplicates| duplicates.max_by { |row| row["source_priority"].to_i } }
    end

    def metric_row_key(row, source_type)
      case source_type
      when :gsc
        [
          row["date"].to_s,
          normalize_url(row["page"]),
          row["query"].to_s.downcase.squish,
          decimal(row["impressions"]).to_s("F"),
          decimal(row["clicks"]).to_s("F"),
          decimal(row["position"]).round(4).to_s("F")
        ]
      when :ga4
        [
          row["date"].to_s,
          normalize_url(row["page"]),
          decimal(row["pageviews"]).to_s("F"),
          decimal(row["active_users"]).to_s("F"),
          decimal(row["sessions"]).to_s("F"),
          decimal(row["event_count"]).to_s("F")
        ]
      end
    end

    def aggregate_shop_clicks
      rows = Hash.new { |hash, key| hash[key] = empty_shop_click }
      return rows unless defined?(::Suelog::ShopClick)

      article_id_column = first_column(::Suelog::ShopClick, %w[article_id])
      source_url_column = first_column(::Suelog::ShopClick, SHOP_CLICK_URL_COLUMNS)
      click_type_column = first_column(::Suelog::ShopClick, %w[click_type event_type kind action])
      matcher = Aicoo::ArticleUrlMatcher.new(articles:)

      ::Suelog::ShopClick.find_each do |click|
        article_id = article_id_column && safe_attr(click, article_id_column)
        if article_id.blank? && source_url_column
          match = matcher.match(safe_attr(click, source_url_column))
          article_id = match.article_id
        end
        next if article_id.blank?

        row = rows[article_id.to_i].dup
        row = available_shop_click(row)
        click_type = safe_attr(click, click_type_column).to_s if click_type_column
        normalized_type = normalized_click_type(click_type)
        row["total_clicks"] += 1
        row["article_shop_clicks"] += 1 if normalized_type == "article_shop"
        row["shop_clicks"] += 1 if normalized_type == "shop"
        row["phone_clicks"] += 1 if normalized_type == "phone"
        row["map_clicks"] += 1 if normalized_type == "map"
        row["affiliate_clicks"] += 1 if normalized_type == "affiliate"
        row["click_type_counts"][normalized_type] = row["click_type_counts"].fetch(normalized_type, 0) + 1
        rows[article_id.to_i] = row
      end
      rows
    rescue StandardError
      Hash.new { |hash, key| hash[key] = empty_shop_click }
    end

    def available_shop_click(row)
      return row if row["available"]

      {
        "available" => true,
        "total_clicks" => 0,
        "article_shop_clicks" => 0,
        "shop_clicks" => 0,
        "phone_clicks" => 0,
        "map_clicks" => 0,
        "affiliate_clicks" => 0,
        "click_type_counts" => {}
      }
    end

    def normalized_click_type(value)
      text = value.to_s.downcase
      return "phone" if text.include?("phone") || text.include?("tel")
      return "map" if text.include?("map")
      return "affiliate" if text.include?("affiliate")
      return "article_shop" if text.include?("article_shop") || text.include?("article")
      return "shop" if text.include?("shop")

      text.presence || "unknown"
    end

    def gsc_rows
      @gsc_rows ||= normalize_gsc_rows(raw_rows_for("gsc"))
    end

    def ga4_rows
      @ga4_rows ||= normalize_ga4_rows(raw_rows_for("ga4"))
    end

    def raw_rows_for(source_type)
      selected_snapshots = latest_snapshots_for(source_type)
      return selected_snapshots.flat_map { |snapshot| rows_from_snapshot(snapshot) } if selected_snapshots.any?

      latest_imports_for(source_type).flat_map { |import| rows_from_import(import) }
    end

    def latest_snapshots_for(source_type)
      snapshots = snapshots_for(source_type)
      latest_day = snapshots.filter_map { |snapshot| snapshot.captured_at&.to_date }.max
      return [] unless latest_day

      snapshots
        .select { |snapshot| snapshot.captured_at&.to_date == latest_day }
        .uniq { |snapshot| snapshot.payload.to_h["snapshot_fingerprint"].presence || legacy_snapshot_fingerprint(snapshot) }
    end

    def latest_imports_for(source_type)
      imports = data_imports_for(source_type)
      latest_day = imports.filter_map { |data_import| data_import.imported_at&.to_date }.max
      return [] unless latest_day

      imports.select { |data_import| data_import.imported_at&.to_date == latest_day }
    end

    def data_imports_for(source_type)
      ids = business.data_sources.where(source_type:).joins(:data_imports).pluck("data_imports.id")
      site_ids = analytics_site_ids
      ids += DataImport.joins(:data_source).where(data_sources: { source_type: }, aicoo_analytics_site_id: site_ids).pluck(:id) if site_ids.any?
      DataImport.where(id: ids.uniq).includes(:data_source, :aicoo_analytics_site).recent.limit(20).to_a
    end

    def snapshots_for(source_type)
      metric_snapshots_for(source_type)
    end

    def metric_snapshots_for(source_type, include_inactive: false)
      import_ids = data_imports_for(source_type).map(&:id)
      AicooDataSnapshot.where(source_type:).recent.limit(100).select do |snapshot|
        payload = snapshot.payload.to_h.deep_stringify_keys
        next false if !include_inactive && inactive_metric_snapshot?(snapshot)

        payload["business_id"].to_i == business.id ||
          analytics_site_ids.map(&:to_s).include?(payload["analytics_site_id"].to_s) ||
          import_ids.include?(snapshot.source_id.to_i)
      end
    end

    def inactive_metric_snapshot?(snapshot)
      snapshot_status(snapshot).in?(%w[archived ignored])
    end

    def snapshot_status(snapshot)
      snapshot.payload.to_h.deep_stringify_keys["snapshot_status"].presence || "active"
    end

    def analytics_site_ids
      @analytics_site_ids ||= begin
        ids = AicooAnalyticsSite.where(business_id: business.id).pluck(:id)
        ids += AicooAnalyticsSite.where(gsc_site_url: business.gsc_site_url).pluck(:id) if business.respond_to?(:gsc_site_url) && business.gsc_site_url.present?
        ids.uniq
      end
    end

    def rows_from_import(data_import)
      rows = rows_from_csv(data_import.processed_text)
      rows = rows_from_json(data_import.raw_text) if rows.empty?
      rows.map do |row|
        row.merge(
          "source_model" => "DataImport",
          "source_id" => data_import.id,
          "source_table" => "data_imports",
          "imported_at" => data_import.imported_at&.iso8601
        )
      end
    end

    def rows_from_snapshot(snapshot)
      payload = snapshot.payload.to_h.deep_stringify_keys
      rows = payload["rows"] || payload.dig("metrics", "rows")
      rows = payload["metrics"] if rows.blank? && payload["metrics"].is_a?(Array)
      Array(rows).map do |row|
        row.to_h.deep_stringify_keys.merge(
          "source_model" => "AicooDataSnapshot",
          "source_id" => snapshot.id,
          "source_table" => "aicoo_data_snapshots",
          "captured_at" => snapshot.captured_at&.iso8601
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

    def normalize_gsc_rows(rows)
      rows.filter_map do |row|
        query = first_present(row["query"], row["検索クエリ"], row["keyword"], Array(row["keys"]).first)
        page = first_present(row["page"], row["ページ"], row["url"], row["landing_page"])
        next if page.blank?

        {
          "query" => query,
          "page" => page,
          "impressions" => decimal(first_present(row["impressions"], row["表示回数"])),
          "clicks" => decimal(first_present(row["clicks"], row["クリック数"])),
          "ctr" => decimal(first_present(row["ctr"], row["CTR"], row["current_ctr"])),
          "position" => decimal(first_present(row["position"], row["掲載順位"], row["平均掲載順位"], row["average_position"])),
          "date" => first_present(row["date"], row["日付"], row["start_date"], row["end_date"]),
          "source_model" => row["source_model"],
          "source_id" => row["source_id"],
          "source_priority" => source_priority(row)
        }
      end
    end

    def normalize_ga4_rows(rows)
      rows.filter_map do |row|
        page = ga4_page_value(row)
        next if page.blank?

        {
          "page" => page,
          "pageviews" => decimal(first_present(row["pageviews"], row["page_views"], row["screenPageViews"], row["views"], metric_value(row, 0))),
          "active_users" => decimal(first_present(row["active_users"], row["activeUsers"], row["users"], row["totalUsers"], metric_value(row, 1))),
          "sessions" => decimal(first_present(row["sessions"], metric_value(row, 2))),
          "engagement_seconds" => decimal(first_present(row["engagement_seconds"], row["userEngagementDuration"], row["averageEngagementTime"], row["average_engagement_time_seconds"], metric_value(row, 4))),
          "event_count" => decimal(first_present(row["event_count"], row["eventCount"], metric_value(row, 3))),
          "landing_page_views" => decimal(first_present(row["landing_page_views"], row["landingPageViews"])),
          "date" => first_present(row["date"], row["日付"], row["start_date"], row["end_date"]),
          "source_model" => row["source_model"],
          "source_id" => row["source_id"],
          "source_priority" => source_priority(row)
        }
      end
    end

    def ga4_page_value(row)
      first_present(
        row["page_path"],
        row["landing_page"],
        row["page_location"],
        row["pageLocation"],
        row["page"],
        row["url"],
        row["pagePath"],
        row["fullPageUrl"],
        dimension_page_value(row)
      )
    end

    def dimension_page_value(row)
      values = row["dimensionValues"]
      return if values.blank?

      candidates = Array(values).filter_map { |value| value.to_h["value"].presence || value.to_s.presence }
      candidates.find { |value| value.to_s.start_with?("/") || value.to_s.match?(%r{\Ahttps?://}i) || value.to_s.include?("/articles/") }
    end

    def metric_value(row, index)
      Array(row["metricValues"]).filter_map { |value| value.to_h["value"].presence }[index]
    end

    def article_payload(article)
      content, content_source = article_content_with_source(article)
      text_content = plain_text(content)
      {
        "published_at" => safe_attr(article, "published_at")&.iso8601,
        "updated_at" => safe_attr(article, "updated_at")&.iso8601,
        "title" => safe_attr(article, "title"),
        "word_count" => text_content.present? ? text_content.length : nil,
        "content_source" => content_source,
        "shop_count" => article_shop_count(article),
        "verified_shop_count" => verified_shop_count(article),
        "internal_link_count" => content.present? ? internal_link_count(content) : nil,
        "category" => first_existing_attr(article, %w[category category_name]),
        "genre" => first_existing_attr(article, %w[genre genres]),
        "area" => first_existing_attr(article, %w[area recommended_areas local_area])
      }
    end

    def article_shop_count(article)
      return safe_attr(article, "shop_count").to_i if article.respond_to?(:shop_count) && safe_attr(article, "shop_count").present?
      return article.shops.count if article.respond_to?(:shops)
      return article_join_rows(article).count if article_join_table
      return article_shop_ids_from_columns(article).size if article_shop_ids_from_columns(article).any?
      return shop_click_shop_ids_for_article(article).size if shop_click_shop_ids_for_article(article).any?

      nil
    rescue StandardError
      nil
    end

    def verified_shop_count(article)
      return safe_attr(article, "verified_shop_count").to_i if article.respond_to?(:verified_shop_count) && safe_attr(article, "verified_shop_count").present?

      shops = shops_for_article(article)
      return nil unless shops

      verified_column = %w[verified smoking_verified smoking_confirmed confirmed approved].find { |column| shops.klass.column_names.include?(column) }
      verified_column ? shops.where(verified_column => true).count : nil
    rescue StandardError
      nil
    end

    def article_content_with_source(article)
      article_content_columns.each do |column|
        value = safe_attr(article, column)
        return [ value, column ] if value.present?
      end

      action_text_content = action_text_content_for(article)
      return action_text_content if action_text_content.first.present?

      table_content = content_from_related_tables(article)
      return table_content if table_content.first.present?

      association_content = content_from_associations(article)
      return association_content if association_content.first.present?

      [ nil, nil ]
    end

    def article_content_columns
      return [] unless suelog_available?

      forbidden = /\A(summary|meta|description|title|excerpt|lead|abstract|og_|seo_)/i
      ::Suelog::Article.column_names.select do |column|
        column.match?(/body|content|markdown|html|text|article_body|main_text|rendered_body|published_body|rich_text/i) &&
          !column.match?(forbidden)
      end
    end

    def action_text_content_for(article)
      return [ nil, nil ] unless table_exists?("action_text_rich_texts")

      connection = ::Suelog::Article.connection
      record_types = [ article.class.name, "::#{article.class.name}", "Article", "Suelog::Article" ].uniq
      sql = ::Suelog::Article.sanitize_sql_array([
        "SELECT name, body FROM action_text_rich_texts WHERE record_id = ? AND record_type IN (?) ORDER BY updated_at DESC, id DESC LIMIT 1",
        article.id,
        record_types
      ])
      row = connection.exec_query(sql).first
      body = row && row["body"]
      return [ body, "action_text:#{row['name']}" ] if body.present?

      [ nil, nil ]
    rescue StandardError
      [ nil, nil ]
    end

    def content_from_related_tables(article)
      connection = ::Suelog::Article.connection
      content_table_candidates.each do |table|
        columns = connection.columns(table).map(&:name)
        article_id_column = columns.find { |column| column == "article_id" || column == "record_id" || column.match?(/article.*id/) }
        content_column = columns.find { |column| content_column_name?(column) }
        next unless article_id_column && content_column

        order_clause = columns.include?("id") ? " ORDER BY id DESC" : ""
        sql = ::Suelog::Article.sanitize_sql_array([
          "SELECT #{connection.quote_column_name(content_column)} AS content_value FROM #{connection.quote_table_name(table)} WHERE #{connection.quote_column_name(article_id_column)} = ?#{order_clause} LIMIT 1",
          article.id
        ])
        row = connection.exec_query(sql).first
        value = row && row["content_value"]
        return [ value, "#{table}.#{content_column}" ] if value.present?
      end
      [ nil, nil ]
    rescue StandardError
      [ nil, nil ]
    end

    def content_from_associations(article)
      article.class.reflect_on_all_associations.each do |reflection|
        next unless reflection.name.to_s.match?(/content|body|rich_text|block|section/i)
        next unless article.respond_to?(reflection.name)

        associated = article.public_send(reflection.name)
        records = associated.respond_to?(:to_a) && !associated.is_a?(String) ? associated.to_a : [ associated ]
        records.compact.each do |record|
          content_column = record.class.column_names.find { |column| content_column_name?(column) } if record.class.respond_to?(:column_names)
          next unless content_column

          value = safe_attr(record, content_column)
          return [ value, "#{reflection.name}.#{content_column}" ] if value.present?
        end
      end
      [ nil, nil ]
    rescue StandardError
      [ nil, nil ]
    end

    def content_table_candidates
      return [] unless suelog_available?

      @content_table_candidates ||= ::Suelog::Article.connection.tables.select do |table|
        table.match?(/article.*(content|body|block|section)|(?:content|body|block|section).*article|action_text_rich_texts/i)
      end
    rescue StandardError
      []
    end

    def content_column_name?(column)
      column.match?(/body|content|markdown|html|text|rich_text/i) &&
        !column.match?(/\A(summary|meta|description|title|excerpt|lead|abstract|og_|seo_)/i)
    end

    def table_exists?(table)
      suelog_available? && ::Suelog::Article.connection.table_exists?(table)
    rescue StandardError
      false
    end

    def article_join_table
      @article_join_table ||= begin
        tables = ::Suelog::Article.connection.tables
        preferred = %w[
          article_shops articles_shops article_shop_relations article_shop_links
          article_shop_assignments article_shop_items article_restaurants article_places
          article_shop_lists article_shop_mappings
        ]
        tables.find { |table| preferred.include?(table) } ||
          tables.find { |table| table.match?(/article.*(shop|restaurant|place)|(?:shop|restaurant|place).*article/) }
      end
    rescue StandardError
      nil
    end

    def article_join_columns
      @article_join_columns ||= begin
        return {} unless article_join_table

        columns = ::Suelog::Article.connection.columns(article_join_table).map(&:name)
        {
          article_id: columns.find { |column| column == "article_id" || column.match?(/article.*id/) },
          shop_id: columns.find { |column| column.in?(%w[shop_id restaurant_id place_id]) || column.match?(/(?:shop|restaurant|place).*id/) }
        }
      end
    end

    def article_join_rows(article)
      return [] unless article_join_table && article_join_columns[:article_id]

      connection = ::Suelog::Article.connection
      sql = ::Suelog::Article.sanitize_sql_array([
        "SELECT * FROM #{connection.quote_table_name(article_join_table)} WHERE #{connection.quote_column_name(article_join_columns[:article_id])} = ?",
        article.id
      ])
      connection.exec_query(sql).to_a
    end

    def shops_for_article(article)
      return article.shops if article.respond_to?(:shops)

      shop_ids = if article_join_table && article_join_columns[:shop_id]
                   article_join_rows(article).filter_map { |row| row[article_join_columns[:shop_id]].presence }.uniq
                 else
                   []
                 end
      shop_ids = article_shop_ids_from_columns(article) if shop_ids.empty?
      shop_ids = shop_click_shop_ids_for_article(article) if shop_ids.empty?
      return ::Suelog::Shop.none if shop_ids.empty?

      ::Suelog::Shop.where(id: shop_ids)
    end

    def article_shop_ids_from_columns(article)
      id_columns = article.class.column_names.grep(/shop.*ids|restaurant.*ids|place.*ids/i)
      id_columns.flat_map do |column|
        extract_ids(safe_attr(article, column))
      end.uniq
    rescue StandardError
      []
    end

    def shop_click_shop_ids_for_article(article)
      return [] unless defined?(::Suelog::ShopClick)

      article_id_column = first_column(::Suelog::ShopClick, %w[article_id])
      shop_id_column = first_column(::Suelog::ShopClick, %w[shop_id restaurant_id place_id])
      return [] unless article_id_column && shop_id_column

      ::Suelog::ShopClick.where(article_id_column => article.id).where.not(shop_id_column => nil).distinct.pluck(shop_id_column)
    rescue StandardError
      []
    end

    def extract_ids(value)
      case value
      when Array
        value
      when Hash
        value.values
      else
        text = value.to_s
        return [] if text.blank?

        parsed = JSON.parse(text) rescue nil
        return extract_ids(parsed) if parsed

        text.scan(/\d+/)
      end.map(&:to_i).reject(&:zero?)
    end

    def internal_link_count(content)
      html = content.to_s
      hrefs = html.scan(/href=["']([^"']+)["']/i).flatten
      inline_paths = html.scan(%r{/(?:articles|shops|umeda|namba|shinsaibashi|kitashinchi|higashidori|sonezaki)[^\s"'<>)]*}i)
      (hrefs + inline_paths).uniq.count { |value| internal_link?(value) }
    end

    def internal_link?(value)
      text = value.to_s
      return true if text.start_with?("/") && text.match?(%r{\A/(?:articles|shops|umeda|namba|shinsaibashi|kitashinchi|higashidori|sonezaki)(?:/|\z)}i)
      return false unless text.match?(%r{\Ahttps?://}i)

      uri = URI.parse(text)
      uri.host.to_s.downcase.in?(%w[suelog.jp www.suelog.jp])
    rescue URI::InvalidURIError
      false
    end

    def plain_text(content)
      ActionView::Base.full_sanitizer.sanitize(content.to_s).squish
    end

    def business_metric_payload
      @business_metric_payload ||= begin
        rows = business.business_metric_dailies.where(recorded_on: 90.days.ago.to_date..Date.current)
        {
          "period_days" => 90,
          "impressions" => rows.sum(:impressions),
          "clicks" => rows.sum(:clicks),
          "pageviews" => rows.sum(:pageviews),
          "sessions" => rows.sum(:sessions),
          "phone_clicks" => rows.sum(:phone_clicks),
          "map_clicks" => rows.sum(:map_clicks),
          "affiliate_clicks" => rows.sum(:affiliate_clicks),
          "conversions" => rows.sum(:conversions)
        }
      end
    end

    def learning_payload(article, normalized_path)
      matching = learning_results_for(article, normalized_path)
      last_result = matching.max_by(&:evaluated_on)
      {
        "improvement_count" => matching.size,
        "improvement_success_count" => matching.count { |result| result.actual_profit_yen.to_i.positive? },
        "last_improvement_at" => last_result&.evaluated_on&.iso8601,
        "last_improvement_summary" => last_result&.note.to_s.presence || last_result&.action_candidate&.title,
        "action_result_ids" => matching.map(&:id)
      }
    end

    def learning_results_for(article, normalized_path)
      slug = safe_attr(article, "slug").to_s
      title = safe_attr(article, "title").to_s
      learning_results.select do |result|
        candidate = result.action_candidate
        metadata = candidate&.metadata.to_h
        text = [
          candidate&.title,
          candidate&.description,
          candidate&.execution_prompt,
          metadata["target_url"],
          metadata["planned_url"],
          metadata["proposed_url"],
          metadata["source_query"],
          metadata["query"]
        ].compact.join(" ")
        text.include?(normalized_path.to_s) ||
          (slug.present? && text.include?(slug)) ||
          (title.present? && text.include?(title))
      end
    end

    def learning_results
      @learning_results ||= ActionResult
        .evaluated
        .includes(:action_candidate)
        .where(business_id: business.id)
        .where(evaluated_on: 2.years.ago.to_date..Date.current)
        .order(evaluated_on: :desc)
        .limit(500)
        .to_a
    end

    def empty_gsc
      {
        "available" => false,
        "impressions" => nil,
        "clicks" => nil,
        "ctr" => nil,
        "average_position" => nil,
        "query_count" => nil,
        "top_queries" => []
      }
    end

    def empty_ga4
      {
        "available" => false,
        "pageviews" => nil,
        "active_users" => nil,
        "sessions" => nil,
        "engagement_seconds" => nil,
        "event_count" => nil,
        "landing_page_views" => nil,
        "page_path" => nil,
        "first_seen" => nil,
        "last_seen" => nil
      }
    end

    def empty_shop_click
      {
        "available" => false,
        "total_clicks" => nil,
        "article_shop_clicks" => nil,
        "shop_clicks" => nil,
        "phone_clicks" => nil,
        "map_clicks" => nil,
        "affiliate_clicks" => nil,
        "click_type_counts" => {}
      }
    end

    def source_priority(row)
      row["source_model"].to_s == "AicooDataSnapshot" ? 2 : 1
    end

    def article_path(article)
      return article.public_path if article.respond_to?(:public_path) && safe_attr(article, "slug").present?

      first_existing_attr(article, ARTICLE_URL_COLUMNS)
    end

    def article_canonical_url(article)
      first_existing_attr(article, %w[canonical_url canonical public_url url])
    end

    def normalized_article_path(article)
      normalize_url(article_canonical_url(article) || article_path(article))
    end

    def normalize_url(value)
      Aicoo::UrlNormalizer.call(value)
    end

    def first_present(*values)
      values.find { |value| value.present? }
    end

    def decimal(value)
      value.to_s.delete(",").to_d
    end

    def average(values)
      values = values.compact_blank
      return 0.to_d if values.empty?

      values.sum.to_d / values.size
    end

    def parse_date(value)
      return if value.blank?

      text = value.to_s
      text = "#{text[0, 4]}-#{text[4, 2]}-#{text[6, 2]}" if text.match?(/\A\d{8}\z/)
      Date.parse(text)
    rescue ArgumentError
      nil
    end

    def column?(model, column)
      model.column_names.include?(column)
    end

    def first_column(model, candidates)
      candidates.find { |column| column?(model, column) }
    end

    def order_column(model)
      first_column(model, %w[published_at updated_at created_at id]) || "id"
    end

    def safe_attr(record, attr)
      return unless record && attr && record.respond_to?(attr)

      record.public_send(attr)
    end

    def first_existing_attr(record, attrs)
      attrs.lazy.map { |attr| safe_attr(record, attr) }.find(&:present?)
    end
  end
end
