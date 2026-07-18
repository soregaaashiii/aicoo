require "csv"
require "cgi"
require "json"
require "set"
require "uri"

module Aicoo
  class SuelogArticleDataSourcesDiagnostic
    SAMPLE_LIMIT = 20
    CLICK_TYPES = %w[phone map affiliate article_shop].freeze
    ARTICLE_URL_COLUMNS = %w[url canonical_url public_url source_url path page_path].freeze
    SHOP_CLICK_URL_COLUMNS = %w[source_url source_article_url article_url page_path path url referrer_url].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(business:)
      @business = business
      @lines = []
      @blocking_reasons = []
    end

    def call
      section("吸えログ記事データソース診断")
      line("business_id=#{business.id}")
      line("business_name=#{business.name}")
      line("generated_at=#{Time.current.iso8601}")

      diagnose_gsc
      diagnose_ga4
      diagnose_shop_click
      diagnose_articles
      diagnose_url_joins
      diagnose_summary

      lines.join("\n")
    end

    private

    attr_reader :business, :lines, :blocking_reasons

    def diagnose_gsc
      section("GSC診断")
      imports = data_imports_for("gsc")
      snapshots = snapshots_for("gsc")
      rows = gsc_rows(imports:, snapshots:)
      page_rows = rows.select { |row| row["page"].present? }
      query_rows = rows.select { |row| row["query"].present? }
      query_page_rows = rows.select { |row| row["query"].present? && row["page"].present? }

      line("最新取得日時=#{latest_time(imports.map(&:imported_at) + snapshots.map(&:captured_at)) || '-'}")
      line("保存レコード数=#{stored_row_count(imports:, snapshots:)}")
      line("対象期間=#{date_range(rows)}")
      line("query単位レコード数=#{query_rows.size}")
      line("page単位レコード数=#{page_rows.size}")
      line("query+page単位レコード数=#{query_page_rows.size}")
      line("取得元モデル名=#{source_models(rows).join(',').presence || '-'}")
      line("取得元DataImport=#{imports.map(&:id).join(',').presence || '-'}")
      line("取得元Snapshot=#{snapshots.map(&:id).join(',').presence || '-'}")
      line("最新エラー=#{latest_error_for('gsc') || '-'}")
      line("page情報欠落=#{query_rows.any? && page_rows.empty?}")
      line("page URLのサンプル20件")
      sample_values(page_rows.map { |row| row["page"] }).each { |value| line("- #{value}") }
      line("impressions/clicks上位20ページ")
      rows.group_by { |row| normalize_url(row["page"]) }.filter_map do |path, grouped|
        next if path.blank?

        {
          path:,
          impressions: grouped.sum { |row| decimal(row["impressions"]) },
          clicks: grouped.sum { |row| decimal(row["clicks"]) },
          raw: grouped.first["page"]
        }
      end.sort_by { |row| [ -row[:impressions], -row[:clicks] ] }.first(SAMPLE_LIMIT).each do |row|
        line("- page=#{row[:raw]} normalized=#{row[:path]} impressions=#{row[:impressions].to_i} clicks=#{row[:clicks].to_i}")
      end
    end

    def diagnose_ga4
      section("GA4診断")
      imports = data_imports_for("ga4")
      snapshots = snapshots_for("ga4")
      rows = ga4_rows(imports:, snapshots:)
      page_rows = rows.select { |row| row["page"].present? }
      events = rows.filter_map { |row| row["event_name"].presence }.uniq

      line("最新取得日時=#{latest_time(imports.map(&:imported_at) + snapshots.map(&:captured_at)) || '-'}")
      line("保存レコード数=#{stored_row_count(imports:, snapshots:)}")
      line("対象期間=#{date_range(rows)}")
      line("page_path/landing_page単位データ件数=#{page_rows.size}")
      line("pageviews=#{rows.sum { |row| decimal(row['pageviews']) }.to_i}")
      line("active_users=#{rows.sum { |row| decimal(row['active_users']) }.to_i}")
      line("sessions=#{rows.sum { |row| decimal(row['sessions']) }.to_i}")
      line("engagement_seconds=#{rows.sum { |row| decimal(row['engagement_seconds']) }.to_i}")
      line("イベント=#{events.first(SAMPLE_LIMIT).join(',').presence || '-'}")
      line("取得元モデル名=#{source_models(rows).join(',').presence || '-'}")
      line("最新エラー=#{latest_error_for('ga4') || '-'}")
      line("fallback判定=#{ga4_fallback_reason(rows)}")
      line("ページURLのサンプル20件")
      sample_values(page_rows.map { |row| row["page"] }).each { |value| line("- #{value}") }
      line("PV上位20ページ")
      rows.group_by { |row| normalize_url(row["page"]) }.filter_map do |path, grouped|
        next if path.blank?

        {
          path:,
          pageviews: grouped.sum { |row| decimal(row["pageviews"]) },
          active_users: grouped.sum { |row| decimal(row["active_users"]) },
          raw: grouped.first["page"]
        }
      end.sort_by { |row| -row[:pageviews] }.first(SAMPLE_LIMIT).each do |row|
        line("- page=#{row[:raw]} normalized=#{row[:path]} pageviews=#{row[:pageviews].to_i} active_users=#{row[:active_users].to_i}")
      end
    end

    def diagnose_shop_click
      section("ShopClick診断")
      unless suelog_available?
        line("Suelog接続=unavailable")
        line("理由=#{@suelog_error}")
        blocking_reasons << "SUELOG_DATABASE_URLまたはSuelog接続が利用できない"
        return
      end

      scope = Suelog::ShopClick.all
      recent_scope = scope
      recent_scope = recent_scope.where(created_at: 90.days.ago..) if column?(Suelog::ShopClick, "created_at")
      click_type_column = first_column(Suelog::ShopClick, %w[click_type event_type kind action])
      article_id_column = first_column(Suelog::ShopClick, %w[article_id])
      source_url_column = first_column(Suelog::ShopClick, SHOP_CLICK_URL_COLUMNS)
      shop_id_column = first_column(Suelog::ShopClick, %w[shop_id])

      line("総レコード数=#{scope.count}")
      line("直近90日件数=#{recent_scope.count}")
      CLICK_TYPES.each do |type|
        count = click_type_column ? scope.where(click_type_column => type).count : 0
        line("click_type.#{type}=#{count}")
      end
      line("article_idを持つ件数=#{article_id_column ? scope.where.not(article_id_column => nil).count : 0}")
      line("source article URLを持つ件数=#{source_url_column ? scope.where.not(source_url_column => [ nil, '' ]).count : 0}")
      line("shop_idのみの件数=#{shop_id_only_count(scope, article_id_column:, source_url_column:, shop_id_column:)}")
      line("記事と結合できない件数=#{unjoinable_shop_click_count(scope, article_id_column:, source_url_column:)}")
      line("結合に利用可能なカラム=#{[article_id_column, source_url_column, shop_id_column, click_type_column].compact.join(',').presence || '-'}")
      line("記事別クリック上位20件")
      article_click_rows(scope, article_id_column:, source_url_column:).first(SAMPLE_LIMIT).each do |row|
        line("- article_id=#{row[:article_id] || '-'} article_url=#{row[:article_url] || '-'} clicks=#{row[:clicks]}")
      end
    rescue StandardError => e
      line("ShopClick診断エラー=#{e.class}: #{e.message}")
      blocking_reasons << "ShopClick診断エラー: #{e.class}"
    end

    def diagnose_articles
      section("Article診断")
      unless suelog_available?
        line("Suelog接続=unavailable")
        line("理由=#{@suelog_error}")
        return
      end

      scope = Suelog::Article.all
      published = published_article_scope
      line("記事総数=#{scope.count}")
      line("公開記事数=#{published.count}")
      line("記事URLのサンプル20件")
      article_records(published).first(SAMPLE_LIMIT).each do |article|
        line([
          "- article_id=#{article.id}",
          "slug=#{safe_attr(article, 'slug') || '-'}",
          "canonical=#{article_canonical_url(article) || '-'}",
          "path=#{article_path(article) || '-'}",
          "title=#{safe_attr(article, 'title') || '-'}",
          "カテゴリ=#{first_existing_attr(article, %w[category category_name]) || '-'}",
          "タグ=#{first_existing_attr(article, %w[tags tag_list tag_names]) || '-'}",
          "エリア=#{first_existing_attr(article, %w[area recommended_areas local_area]) || '-'}",
          "ジャンル=#{first_existing_attr(article, %w[genre genres]) || '-'}",
          "内部リンク情報=#{internal_link_available?(article)}"
        ].join(" "))
      end
    rescue StandardError => e
      line("Article診断エラー=#{e.class}: #{e.message}")
      blocking_reasons << "Article診断エラー: #{e.class}"
    end

    def diagnose_url_joins
      section("URL正規化診断")
      unless suelog_available?
        line("Suelog接続=unavailable")
        line("理由=#{@suelog_error}")
        return
      end

      line("正規化ルール=scheme削除, host削除, 末尾スラッシュ統一, query削除, fragment削除, URL decode, lowercase, www削除, canonical優先")
      gsc_pages = normalized_page_set(gsc_rows(imports: data_imports_for("gsc"), snapshots: snapshots_for("gsc")))
      ga4_pages = normalized_page_set(ga4_rows(imports: data_imports_for("ga4"), snapshots: snapshots_for("ga4")))
      shop_pages = normalized_shop_click_pages

      article_records(published_article_scope).first(SAMPLE_LIMIT).each do |article|
        url = article_canonical_url(article) || article_path(article)
        normalized = normalize_url(url)
        gsc_joinable = normalized.present? && gsc_pages.include?(normalized)
        ga4_joinable = normalized.present? && ga4_pages.include?(normalized)
        shopclick_joinable = normalized.present? && shop_pages.include?(normalized)
        line([
          "article_id=#{article.id}",
          "url=#{url || '-'}",
          "normalized=#{normalized || '-'}",
          "GSC結合=#{gsc_joinable}",
          "GA4結合=#{ga4_joinable}",
          "ShopClick結合=#{shopclick_joinable}"
        ].join(" "))
      end
    rescue StandardError => e
      line("URL結合診断エラー=#{e.class}: #{e.message}")
      blocking_reasons << "URL結合診断エラー: #{e.class}"
    end

    def diagnose_summary
      section("診断結果サマリー")
      gsc_rows_cache = gsc_rows(imports: data_imports_for("gsc"), snapshots: snapshots_for("gsc"))
      ga4_rows_cache = ga4_rows(imports: data_imports_for("ga4"), snapshots: snapshots_for("ga4"))
      gsc_pages = normalized_page_set(gsc_rows_cache)
      ga4_pages = normalized_page_set(ga4_rows_cache)
      shop_pages = suelog_available? ? normalized_shop_click_pages : Set.new
      article_paths = suelog_available? ? article_records(published_article_scope).map { |article| normalize_url(article_canonical_url(article) || article_path(article)) }.compact_blank : []

      gsc_joinable = article_paths.count { |path| gsc_pages.include?(path) }
      ga4_joinable = article_paths.count { |path| ga4_pages.include?(path) }
      shop_joinable = article_paths.count { |path| shop_pages.include?(path) }

      line("gsc_connected=#{data_imports_for('gsc').any? || snapshots_for('gsc').any?}")
      line("gsc_page_data_available=#{gsc_pages.any?}")
      line("ga4_connected=#{data_imports_for('ga4').any? || snapshots_for('ga4').any?}")
      line("ga4_page_data_available=#{ga4_pages.any?}")
      line("shopclick_available=#{suelog_available? && Suelog::ShopClick.exists?}")
      line("article_url_available=#{article_paths.any?}")
      line("gsc_joinable_article_count=#{gsc_joinable}")
      line("ga4_joinable_article_count=#{ga4_joinable}")
      line("shopclick_joinable_article_count=#{shop_joinable}")
      line("fully_joinable_article_count=#{article_paths.count { |path| gsc_pages.include?(path) && ga4_pages.include?(path) && shop_pages.include?(path) }}")
      collect_blocking_reasons(gsc_rows_cache:, ga4_rows_cache:, article_paths:, gsc_pages:, ga4_pages:, shop_pages:)
      line("blocking_reasons=#{blocking_reasons.uniq.join(' / ').presence || '-'}")
    end

    def collect_blocking_reasons(gsc_rows_cache:, ga4_rows_cache:, article_paths:, gsc_pages:, ga4_pages:, shop_pages:)
      blocking_reasons << "GSCデータなし" if gsc_rows_cache.empty?
      blocking_reasons << "GSC page列なし" if gsc_rows_cache.any? && gsc_pages.empty?
      blocking_reasons << "GA4データなし" if ga4_rows_cache.empty?
      blocking_reasons << "GA4 page_path/landing_page列なし" if ga4_rows_cache.any? && ga4_pages.empty?
      blocking_reasons << "Article URLなし" if article_paths.empty?
      blocking_reasons << "GSCとArticle URLが結合できない" if article_paths.any? && gsc_pages.any? && article_paths.none? { |path| gsc_pages.include?(path) }
      blocking_reasons << "GA4とArticle URLが結合できない" if article_paths.any? && ga4_pages.any? && article_paths.none? { |path| ga4_pages.include?(path) }
      blocking_reasons << "ShopClickとArticle URLが結合できない" if article_paths.any? && shop_pages.any? && article_paths.none? { |path| shop_pages.include?(path) }
    end

    def data_imports_for(source_type)
      @data_imports_for ||= {}
      @data_imports_for[source_type] ||= begin
        ids = business.data_sources.where(source_type:).joins(:data_imports).pluck("data_imports.id")
        site_ids = analytics_site_ids
        if site_ids.any?
          ids += DataImport.joins(:data_source).where(data_sources: { source_type: }, aicoo_analytics_site_id: site_ids).pluck(:id)
        end
        DataImport.where(id: ids.uniq).includes(:data_source, :aicoo_analytics_site).recent.limit(20).to_a
      end
    end

    def snapshots_for(source_type)
      @snapshots_for ||= {}
      @snapshots_for[source_type] ||= AicooDataSnapshot.where(source_type:).recent.limit(100).select do |snapshot|
        payload = snapshot.payload.to_h.deep_stringify_keys
        payload["business_id"].to_i == business.id ||
          analytics_site_ids.map(&:to_s).include?(payload["analytics_site_id"].to_s) ||
          snapshot.source_id.to_i == business.id ||
          data_imports_for(source_type).map(&:id).include?(snapshot.source_id.to_i)
      end
    end

    def analytics_site_ids
      @analytics_site_ids ||= begin
        ids = AicooAnalyticsSite.where(business_id: business.id).pluck(:id)
        ids += AicooAnalyticsSite.where(gsc_site_url: business.gsc_site_url).pluck(:id) if business.gsc_site_url.present?
        ids.uniq
      end
    end

    def gsc_rows(imports:, snapshots:)
      @gsc_rows ||= {}
      key = [ imports.map(&:id), snapshots.map(&:id) ]
      @gsc_rows[key] ||= normalize_gsc_rows(imports.flat_map { |import| rows_from_import(import) } + snapshots.flat_map { |snapshot| rows_from_snapshot(snapshot) })
    end

    def ga4_rows(imports:, snapshots:)
      @ga4_rows ||= {}
      key = [ imports.map(&:id), snapshots.map(&:id) ]
      @ga4_rows[key] ||= normalize_ga4_rows(imports.flat_map { |import| rows_from_import(import) } + snapshots.flat_map { |snapshot| rows_from_snapshot(snapshot) })
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
        next if query.blank? && page.blank?

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
          "source_table" => row["source_table"]
        }
      end
    end

    def normalize_ga4_rows(rows)
      rows.filter_map do |row|
        page = first_present(row["page_path"], row["landing_page"], row["page"], row["url"], row["pagePath"], row["fullPageUrl"], dimension_value(row))
        event_name = first_present(row["event_name"], row["eventName"])
        next if page.blank? && event_name.blank? && metric_values(row).blank?

        {
          "page" => page,
          "pageviews" => decimal(first_present(row["pageviews"], row["page_views"], row["screenPageViews"], row["views"], metric_value(row, 0))),
          "active_users" => decimal(first_present(row["active_users"], row["activeUsers"], row["users"], row["totalUsers"], metric_value(row, 1))),
          "sessions" => decimal(first_present(row["sessions"], metric_value(row, 2))),
          "engagement_seconds" => decimal(first_present(row["engagement_seconds"], row["averageEngagementTime"], row["average_engagement_time_seconds"])),
          "event_name" => event_name,
          "date" => first_present(row["date"], row["日付"], row["start_date"], row["end_date"]),
          "source_model" => row["source_model"],
          "source_id" => row["source_id"],
          "source_table" => row["source_table"]
        }
      end
    end

    def dimension_value(row)
      values = row["dimensionValues"]
      return if values.blank?

      Array(values).filter_map { |value| value.to_h["value"] }.find(&:present?)
    end

    def metric_values(row)
      Array(row["metricValues"]).filter_map { |value| value.to_h["value"] }
    end

    def metric_value(row, index)
      metric_values(row)[index]
    end

    def source_models(rows)
      rows.filter_map { |row| row["source_model"] }.uniq
    end

    def date_range(rows)
      dates = rows.filter_map { |row| row["date"].presence }
      return "-" if dates.empty?

      "#{dates.min}..#{dates.max}"
    end

    def latest_time(times)
      times.compact.max&.iso8601
    end

    def stored_row_count(imports:, snapshots:)
      imports.sum { |import| import.row_count.to_i.nonzero? || rows_from_import(import).size } +
        snapshots.sum { |snapshot| Array(snapshot.payload.to_h.deep_stringify_keys["rows"]).size }
    end

    def latest_error_for(source_type)
      run_error = if defined?(AnalyticsFetchRun)
                    AnalyticsFetchRun.where(source_type:, status: "failed").where.not(error_message: [ nil, "" ]).order(updated_at: :desc).pick(:error_message)
                  end
      google_run_error = if defined?(GoogleApiImportRun)
                           GoogleApiImportRun.where(business:, status: "failed").where.not(error_message: [ nil, "" ]).order(updated_at: :desc).pick(:error_message)
                         end
      setting_error = if defined?(AnalyticsSourceSetting) && AnalyticsSourceSetting.column_names.include?("last_error")
                        AnalyticsSourceSetting.where(source_type:).where.not(last_error: [ nil, "" ]).order(updated_at: :desc).pick(:last_error)
                      end
      setting_error.presence || run_error.presence || google_run_error.presence
    rescue StandardError => e
      "#{e.class}: #{e.message}"
    end

    def ga4_fallback_reason(rows)
      return "ga4_rows_not_found" if rows.empty?
      return "page_level_rows_available" if rows.any? { |row| row["page"].present? }

      "business_or_event_level_rows_without_page_path"
    end

    def suelog_available?
      return @suelog_available if defined?(@suelog_available)

      SuelogRecord.ensure_connection!
      @suelog_available = true
    rescue StandardError => e
      @suelog_error = "#{e.class}: #{e.message}"
      @suelog_available = false
    end

    def article_records(scope)
      scope.order(order_column(Suelog::Article) => :desc).limit(200).to_a
    end

    def published_article_scope
      scope = Suelog::Article.all
      scope = scope.where(published: true) if column?(Suelog::Article, "published")
      scope = scope.where("published_at IS NULL OR published_at <= ?", Time.current) if column?(Suelog::Article, "published_at")
      scope
    end

    def order_column(model)
      first_column(model, %w[published_at updated_at created_at id]) || "id"
    end

    def article_path(article)
      return article.public_path if article.respond_to?(:public_path) && safe_attr(article, "slug").present?

      first_existing_attr(article, ARTICLE_URL_COLUMNS)
    end

    def article_canonical_url(article)
      first_existing_attr(article, %w[canonical_url canonical public_url url])
    end

    def internal_link_available?(article)
      columns = article.class.column_names
      link_columns = columns.grep(/link|body|content|html|markdown/i)
      return false if link_columns.empty?

      link_columns.any? { |column| safe_attr(article, column).to_s.match?(/href=|\/articles\//i) }
    end

    def normalized_page_set(rows)
      Set.new(rows.filter_map { |row| normalize_url(row["page"]) })
    end

    def normalized_shop_click_pages
      return Set.new unless suelog_available?

      source_url_column = first_column(Suelog::ShopClick, SHOP_CLICK_URL_COLUMNS)
      article_id_column = first_column(Suelog::ShopClick, %w[article_id])
      paths = []
      paths += Suelog::ShopClick.where.not(source_url_column => [ nil, "" ]).limit(5000).pluck(source_url_column) if source_url_column
      if article_id_column
        article_ids = Suelog::ShopClick.where.not(article_id_column => nil).limit(5000).pluck(article_id_column).uniq
        paths += Suelog::Article.where(id: article_ids).limit(5000).map { |article| article_canonical_url(article) || article_path(article) }
      end
      Set.new(paths.filter_map { |path| normalize_url(path) })
    rescue StandardError
      Set.new
    end

    def shop_id_only_count(scope, article_id_column:, source_url_column:, shop_id_column:)
      return 0 unless shop_id_column

      scoped = scope.where.not(shop_id_column => nil)
      scoped = scoped.where(article_id_column => nil) if article_id_column
      scoped = scoped.where(source_url_column => [ nil, "" ]) if source_url_column
      scoped.count
    end

    def unjoinable_shop_click_count(scope, article_id_column:, source_url_column:)
      scoped = scope
      scoped = scoped.where(article_id_column => nil) if article_id_column
      scoped = scoped.where(source_url_column => [ nil, "" ]) if source_url_column
      scoped.count
    end

    def article_click_rows(scope, article_id_column:, source_url_column:)
      if article_id_column
        rows = scope.where.not(article_id_column => nil).group(article_id_column).count.map do |article_id, count|
          article = Suelog::Article.find_by(id: article_id)
          { article_id:, article_url: article && (article_canonical_url(article) || article_path(article)), clicks: count }
        end
        return rows.sort_by { |row| -row[:clicks] }
      end

      return [] unless source_url_column

      scope.where.not(source_url_column => [ nil, "" ]).group(source_url_column).count.map do |url, count|
        { article_id: nil, article_url: url, clicks: count }
      end.sort_by { |row| -row[:clicks] }
    end

    def normalize_url(value)
      raw = value.to_s.strip
      return if raw.blank?

      raw = CGI.unescape(raw)
      uri = URI.parse(raw.match?(%r{\Ahttps?://}i) ? raw : "https://suelog.jp#{raw.start_with?('/') ? raw : "/#{raw}"}")
      path = uri.path.to_s.downcase
      path = "/" if path.blank?
      path = path.chomp("/") unless path == "/"
      path
    rescue URI::InvalidURIError
      nil
    end

    def sample_values(values)
      values.compact_blank.uniq.first(SAMPLE_LIMIT)
    end

    def first_present(*values)
      values.find { |value| value.present? }
    end

    def decimal(value)
      value.to_s.delete(",").to_d
    end

    def column?(model, column)
      model.column_names.include?(column)
    end

    def first_column(model, candidates)
      candidates.find { |column| column?(model, column) }
    end

    def safe_attr(record, attr)
      return unless record.respond_to?(attr)

      record.public_send(attr)
    end

    def first_existing_attr(record, attrs)
      attrs.lazy.map { |attr| safe_attr(record, attr) }.find(&:present?)
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
