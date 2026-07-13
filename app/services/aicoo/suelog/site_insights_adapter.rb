module Aicoo
  module Suelog
    class SiteInsightsAdapter
      require "csv"

      Result = Data.define(:created, :skipped) do
        def created_count = created.size
        def skipped_count = skipped.size
        def handled? = true
        def diagnostics
          {
            "created_count" => created_count,
            "skipped_count" => skipped_count,
            "skipped_reasons" => skipped
          }
        end
      end

      GENRE_KEYWORDS = {
        "居酒屋" => %w[居酒屋 酒場 大衆酒場 ネオ居酒屋 飲み 飲み屋],
        "焼肉" => %w[焼肉 ホルモン],
        "焼鳥" => %w[焼鳥 焼き鳥 やきとり],
        "バー" => %w[バー bar],
        "カフェ" => %w[カフェ cafe],
        "喫茶店" => %w[喫茶 喫茶店 純喫茶],
        "ラーメン" => %w[ラーメン],
        "寿司" => %w[寿司 鮨],
        "シーシャ" => %w[シーシャ shisha hookah],
        "個室" => %w[個室 半個室 完全個室 2人個室],
        "デート" => %w[デート 雰囲気 横並び 記念日 女子会],
        "深夜" => %w[深夜 朝まで 始発 24時間 オール],
        "安い" => %w[安い コスパ せんべろ 食べ放題 飲み放題]
      }.freeze

      GENRE_DB_GROUPS = {
        "居酒屋" => %w[居酒屋 酒場 大衆酒場 ネオ居酒屋 立ち飲み 立飲み 焼鳥 焼き鳥 やきとり 串焼き 串焼 串カツ 串かつ 串揚げ 海鮮 魚介 和食 創作料理 ダイニングバー],
        "焼鳥" => %w[焼鳥 焼き鳥 やきとり 串焼き 串焼 鶏料理 鶏肉料理],
        "焼肉" => %w[焼肉 焼き肉 ホルモン],
        "バー" => %w[バー BAR bar パブ ラウンジ ダイニングバー カラオケバー],
        "カフェ" => %w[カフェ cafe Cafe 喫茶 喫茶店 純喫茶],
        "喫茶店" => %w[喫茶 喫茶店 純喫茶 カフェ],
        "寿司" => %w[寿司 鮨 すし],
        "シーシャ" => %w[シーシャ],
        "個室" => %w[個室],
        "デート" => %w[居酒屋 バー ダイニングバー イタリアン フレンチ 焼肉 シーシャ カフェ],
        "深夜" => %w[居酒屋 バー ダイニングバー 焼肉 シーシャ ラーメン],
        "安い" => %w[居酒屋 大衆酒場 立ち飲み 立飲み 串カツ 串かつ 焼鳥 焼き鳥]
      }.freeze

      AREA_KEYWORDS = {
        "梅田" => %w[梅田 大阪駅 東通り お初天神 北新地 堂山 茶屋町 中之島 福島 天満 中崎町 中津 南森町 西天満],
        "難波" => %w[難波 なんば 心斎橋 道頓堀 日本橋 千日前 大国町],
        "京橋" => %w[京橋],
        "西中島" => %w[西中島 西中島南方 南方 新大阪],
        "本町" => %w[本町 淀屋橋 北浜 肥後橋]
      }.freeze

      LOCAL_AREA_KEYWORDS = {
        "曽根崎" => %w[曽根崎 お初天神 東梅田 太融寺],
        "東通り" => %w[東通り 堂山 小松原 阪急東通],
        "お初天神" => %w[お初天神 曽根崎 露天神],
        "東梅田" => %w[東梅田 曽根崎 太融寺 堂山],
        "北新地" => %w[北新地 曽根崎新地],
        "堂山" => %w[堂山 東通り 太融寺],
        "茶屋町" => %w[茶屋町 芝田],
        "太融寺" => %w[太融寺 堂山 東梅田],
        "大阪駅" => %w[大阪駅 梅田 芝田 大深町],
        "日本橋" => %w[日本橋 千日前],
        "心斎橋" => %w[心斎橋 東心斎橋 西心斎橋],
        "道頓堀" => %w[道頓堀 宗右衛門町],
        "中之島" => %w[中之島 堂島 渡辺橋 肥後橋],
        "福島" => %w[福島 新福島 野田 海老江],
        "天満" => %w[天満 天神橋筋六丁目 天六 扇町],
        "中崎町" => %w[中崎町 中崎],
        "中津" => %w[中津 豊崎],
        "南森町" => %w[南森町 大阪天満宮 西天満],
        "西中島" => %w[西中島 西中島南方 南方 新大阪],
        "本町" => %w[本町 淀屋橋 北浜 肥後橋],
        "大国町" => %w[大国町 敷津 今宮]
      }.freeze

      NOISE_KEYWORDS = %w[クチコミ review reviews レビュー instagram インスタ].freeze
      FACILITY_SMOKING_KEYWORDS = %w[喫煙所 喫煙スペース 喫煙室 喫煙エリア].freeze
      REVENUE_FIT = {
        "焼肉" => 1.6, "居酒屋" => 1.5, "焼鳥" => 1.5, "個室" => 1.5,
        "デート" => 1.4, "深夜" => 1.4, "安い" => 1.3, "バー" => 1.2,
        "寿司" => 1.2, "シーシャ" => 1.1, "カフェ" => 0.9, "喫茶店" => 0.8,
        "ラーメン" => 0.8
      }.freeze
      CV_INTENT_KEYWORDS = {
        high: %w[喫煙可 吸える 紙タバコ 紙たばこ 席で吸える 全席喫煙 個室 完全個室 朝まで 深夜 今営業中 営業中 予約 空席],
        medium: %w[居酒屋 バー 焼肉 焼鳥 シーシャ デート 横並び 安い 飲み放題 せんべろ],
        low: NOISE_KEYWORDS
      }.freeze

      def self.target?(business)
        keys = [
          business.project_key,
          business.repository_name,
          business.local_project_path,
          business.metadata.to_h["project_key"],
          business.metadata.to_h["repository_name"]
        ].compact.map(&:to_s)
        keys.any? { |value| value.match?(/\bsuelog\b|\/suelog\z/i) }
      end

      def self.call(...)
        new(...).call
      end

      def initialize(business:, today: Date.current, limit: 200)
        @business = business
        @today = today.to_date
        @limit = limit
      end

      def call
        items = build_items
        return Result.new(created: [], skipped: [ "suelog_site_insights:no_items" ]) if items.empty?

        created = items.sort_by { |item| -item[:expected_score].to_f }.first(limit).filter_map do |item|
          create_candidate(item)
        end
        Result.new(created:, skipped: [])
      end

      private

      attr_reader :business, :today, :limit

      def serp_allowed?
        @serp_allowed ||= Aicoo::DataSourcePolicy.for(business).enabled?(:serp, context: :existing_business_improvement)
      end

      def build_items
        query_rows.filter_map { |row| build_item(row) }.reject { |item| item[:specific_shop_query] }
      end

      def query_rows
        rows = []
        rows.concat(gsc_query_rows)
        rows.concat(metric_query_rows)
        rows.compact_blank.uniq { |row| row[:query] }
      end

      def gsc_query_rows
        latest_gsc_imports.flat_map { |data_import| rows_from_gsc_import(data_import) }
      end

      def metric_query_rows
        return [] if recent_impressions.zero?

        base_queries = [
          [ business.name, "比較" ].compact_blank.join(" "),
          "梅田 喫煙 居酒屋",
          "梅田 喫煙 カフェ",
          "難波 喫煙 居酒屋",
          "東通り 居酒屋 喫煙可",
          "曽根崎 バー 喫煙可能"
        ]
        base_queries.map do |query|
          {
            query:,
            impressions: [ recent_impressions / base_queries.size, 10 ].max,
            clicks: [ recent_clicks / base_queries.size, 0 ].max,
            ctr_percent: recent_ctr_percent,
            position: recent_position,
            source: "business_metric_daily_fallback"
          }
        end
      end

      def build_item(row)
        query = row[:query].to_s.strip
        return if query.blank?
        return if NOISE_KEYWORDS.any? { |keyword| query.downcase.include?(keyword.downcase) }

        area = detect_area(query)
        local_area = detect_local_area(query)
        genre = detect_genre(query)
        theme = detect_theme(query:, landing_page: row[:landing_page])
        cv_intent = detect_cv_intent(query)
        query_type = detect_query_type(query)
        specific_shop_query = query_type == "specific_shop"

        impressions = row[:impressions].to_i
        clicks = row[:clicks].to_i
        ctr_percent = row[:ctr_percent].to_f
        position = row[:position].to_f
        gsc_landing_page_present = row[:landing_page].present?
        raw_landing_page = row[:landing_page].presence || infer_landing_page(area:, local_area:, genre:, theme:)
        target_url = owned_target_url_for(raw_landing_page, area:, local_area:, genre:, theme:)
        return unless target_url.owner_page?
        landing_page = target_url.url

        shops_count = shop_count_for(area:, local_area:, genre:)
        confirmed_count = confirmed_shop_count_for(area:, local_area:, genre:)
        articles = article_relevance_for(query:, area:, local_area:, genre:, theme:)
        page_match = page_match_for(query:, raw_landing_page:, gsc_landing_page_present:, target_url:, articles:)
        articles_count = articles[:count]
        supply_score = [ shops_count + (confirmed_count * 2) + (articles_count * 20), 5 ].max
        revenue_fit = REVENUE_FIT.fetch(genre, 1.0) * cv_intent_multiplier(cv_intent)
        demand_score = impressions + (clicks * 5)
        growth_score = position_multiplier(position) * ctr_multiplier(ctr_percent)
        pv_score = (demand_score * growth_score).round(1)
        revenue_score = (demand_score * growth_score * revenue_fit).round(1)
        db_gap_score = (demand_score.to_f / supply_score).round(1)
        ctr_score = (impressions * ctr_multiplier(ctr_percent)).round(1)
        expected_score = expected_impact_score(
          impressions:,
          position:,
          ctr_percent:,
          supply_score:,
          revenue_fit:,
          cv_intent:
        )
        ga4_data = ga4_data_for(landing_page)
        page_ga4_score = ga4_value_score(ga4_data)
        total_score = total_opportunity_score(expected_score:, ga4_score: page_ga4_score, theme:).round(1)
        recommended_action = recommended_action_for(position:, impressions:, ctr_percent:, shops_count:, articles_count:, ga4_data:)
        work_cost = work_cost_for(recommended_action)
        roi_score = roi_score_for(expected_score: total_score, action: recommended_action)
        strategy = article_strategy_for(
          query_type:,
          specific_shop_query:,
          landing_page:,
          position:,
          ctr_percent:,
          articles_count:,
          article_relevance_score: articles[:best_score],
          local_area:,
          theme:
        )

        item = {
          query:, area:, local_area:, genre:, cv_intent:, query_type:, theme:,
          specific_shop_query:, impressions:, clicks:, ctr_percent: ctr_percent.round(2),
          position: position.round(1), landing_page:,
          raw_landing_page:,
          target_url: landing_page,
          target_url_type: target_url.target_url_type,
          external_reference_urls: [ target_url.reference_url ].compact,
          page_exists: page_match[:page_exists],
          matched_page: page_match[:matched_page],
          recommended_slug: page_match[:recommended_slug],
          creation_type: page_match[:creation_type],
          work_type: page_match[:work_type],
          shops_count:, confirmed_count:, articles_count:,
          article_relevance_count: articles[:count],
          article_relevance_score: articles[:best_score],
          article_relevance_path: articles[:best_path],
          article_relevance_title: articles[:best_title],
          pv_score:, revenue_score:, db_gap_score:, ctr_score:, expected_score:,
          ga4_score: page_ga4_score,
          page_ga4_score:,
          theme_ga4_score: 0,
          total_score:,
          recommended_action:,
          work_cost:,
          roi_score:,
          work_label: work_label_for(recommended_action),
          strategy:,
          strategy_reason: strategy_reason_for(strategy:, position:, ctr_percent:, article_relevance_score: articles[:best_score], local_area:, theme:),
          ga4_views: ga4_data[:views].to_i,
          ga4_active_users: ga4_data[:active_users].to_i,
          ga4_engagement_seconds: ga4_data[:engagement_seconds].to_f.round(1),
          serp_reference: serp_reference_for(query)
        }
        item[:next_move_type] = next_move_type_for(item)
        item[:next_move_score] = next_move_score_for(item).round(1)
        item[:todo] = todo_lines_for(item)
        item[:concrete_task] = concrete_task_for(item)
        item
      end

      def create_candidate(item)
        key = "suelog_site_insights:#{Digest::SHA1.hexdigest([ item[:query], item[:recommended_action], item[:concrete_task] ].join(':')).first(12)}"
        existing = business.action_candidates
          .where(generation_source: "business_analyzer")
          .where("metadata ->> 'suelog_insight_key' = ?", key)
          .where(created_at: (today.beginning_of_day - 7.days)..)
          .first
        return existing if existing

        Aicoo::ActionCandidateUpserter.call(
          business:,
          attributes: {
            title: item[:concrete_task],
            description: "#{item[:query]} / #{item[:recommended_action]} / ROI #{item[:roi_score]}",
            action_type: action_type_for(item),
            generation_source: "business_analyzer",
            status: status_for(item),
            immediate_value_yen: expected_value_yen_for(item),
            expected_hours: item[:work_cost],
            success_probability: success_probability_for(item),
            strategic_value_score: [ item[:next_move_score].to_i, 100 ].min,
            risk_reduction_score: 30,
            confidence_score: 55,
            data_confidence_score: 60,
            evaluation_reason: evaluation_reason_for(item),
            execution_prompt: execution_prompt_for(item),
            metadata: metadata_for(item, key)
          }
        )
      end

      def metadata_for(item, key)
        {
          "suelog_site_insights" => true,
          "suelog_insight_key" => key,
          "source_script" => "script/site_insights.rb",
          "data_sources_used" => %w[gsc ga4 internal],
          "query" => item[:query],
          "area" => item[:area],
          "local_area" => item[:local_area],
          "genre" => item[:genre],
          "cv_intent" => item[:cv_intent],
          "query_type" => item[:query_type],
          "theme" => item[:theme],
          "recommended_action" => item[:recommended_action],
          "next_move_type" => item[:next_move_type],
          "next_move_score" => item[:next_move_score],
          "expected_score" => item[:expected_score],
          "ga4_score" => item[:ga4_score],
          "page_ga4_score" => item[:page_ga4_score],
          "total_score" => item[:total_score],
          "roi_score" => item[:roi_score],
          "work_cost" => item[:work_cost],
          "work_label" => item[:work_label],
          "strategy" => item[:strategy],
          "strategy_reason" => item[:strategy_reason],
          "impressions" => item[:impressions],
          "clicks" => item[:clicks],
          "ctr_percent" => item[:ctr_percent],
          "position" => item[:position],
          "landing_page" => item[:landing_page],
          "raw_landing_page" => item[:raw_landing_page],
          "target_url" => item[:work_type] == "new_article" ? nil : item[:target_url],
          "target_url_type" => item[:target_url_type],
          "external_reference_urls" => item[:external_reference_urls],
          "reference_urls" => item[:external_reference_urls],
          "planned_url" => item[:work_type] == "new_article" ? "/articles/#{item[:recommended_slug]}" : nil,
          "planned_url_type" => item[:work_type] == "new_article" ? "planned_owner_page" : nil,
          "page_exists" => item[:page_exists],
          "matched_page" => item[:matched_page],
          "recommended_slug" => item[:recommended_slug],
          "creation_type" => item[:creation_type],
          "work_type" => item[:work_type],
          "article_candidate" => article_candidate_metadata_for(item),
          "search_query" => article_candidate_metadata_for(item)&.fetch("search_query", nil),
          "search_intent" => article_candidate_metadata_for(item)&.fetch("search_intent", nil),
          "recommended_title" => article_candidate_metadata_for(item)&.fetch("recommended_title", nil),
          "recommended_url_slug" => article_candidate_metadata_for(item)&.fetch("recommended_url_slug", nil),
          "article_summary" => article_candidate_metadata_for(item)&.fetch("article_summary", nil),
          "article_reason" => article_candidate_metadata_for(item)&.fetch("article_reason", nil),
          "expected_pv" => article_candidate_metadata_for(item)&.fetch("expected_pv", nil),
          "expected_ctr_lift" => article_candidate_metadata_for(item)&.fetch("expected_ctr_lift", nil),
          "expected_profit_yen" => expected_value_yen_for(item),
          "priority" => item[:next_move_score],
          "required_data" => article_candidate_metadata_for(item)&.fetch("required_data", nil),
          "shops_count" => item[:shops_count],
          "confirmed_count" => item[:confirmed_count],
          "articles_count" => item[:articles_count],
          "article_relevance_count" => item[:article_relevance_count],
          "article_relevance_score" => item[:article_relevance_score],
          "article_relevance_path" => item[:article_relevance_path],
          "article_relevance_title" => item[:article_relevance_title],
          "ga4_views" => item[:ga4_views],
          "ga4_active_users" => item[:ga4_active_users],
          "ga4_engagement_seconds" => item[:ga4_engagement_seconds],
          "serp_reference" => item[:serp_reference],
          "analysis_priority" => {
            "gsc" => 5,
            "ga4" => 5,
            "business_db" => 4,
            "action_result_learning" => 2,
            "serp" => 1
          },
          "concrete_task" => item[:concrete_task],
          "execution_mode" => execution_mode_for(item),
          "candidate_quality" => "high",
          "action_plan" => action_plan_for(item),
          "execution_units" => execution_units_for(item),
          "evidence" => evidence_for(item)
        }.compact
      end

      def action_plan_for(item)
        target = if item[:work_type] == "new_article"
          "/articles/#{item[:recommended_slug]}"
        else
          item[:target_url].presence || item[:landing_page].presence || item[:query]
        end

        {
          "summary" => item[:concrete_task],
          "goal" => item[:recommended_action],
          "target" => target,
          "owner_next_step" => item[:todo].first,
          "execution_steps" => item[:todo],
          "execution_units" => execution_units_for(item)
        }
      end

      def execution_units_for(item)
        [
          {
            "label" => item[:concrete_task],
            "query" => item[:query],
            "area" => item[:area],
            "local_area" => item[:local_area],
            "genre" => item[:genre],
            "target_amount" => target_amount_for(item),
            "estimated_minutes" => (item[:work_cost].to_d * 60).round,
            "reason" => item[:recommended_action]
          }.compact
        ]
      end

      def evidence_for(item)
        {
          "source" => %w[gsc ga4 business_db],
          "issue_type" => item[:recommended_action],
          "query" => item[:query],
          "page_path" => item[:target_url].presence || item[:landing_page],
          "area" => item[:area],
          "genre" => item[:genre],
          "current_value" => item[:expected_score],
          "benchmark_value" => item[:total_score],
          "target_amount" => target_amount_for(item),
          "reason" => evaluation_reason_for(item)
        }.compact
      end

      def evaluation_reason_for(item)
        [
          "suelog_site_insights:#{item[:recommended_action]}",
          "query=#{item[:query]}",
          "作業種別=#{item[:work_type].presence || '未判定'}",
          "ページ判定=#{item[:page_exists] ? '既存改善' : '新規作成'} / matched_page=#{item[:matched_page].presence || 'なし'} / recommended_slug=#{item[:recommended_slug].presence || '-'}",
          "表示=#{item[:impressions]} / クリック=#{item[:clicks]} / CTR=#{item[:ctr_percent]}% / 順位=#{item[:position]}",
          "対象=#{item[:area] || '未判定'} / #{item[:local_area] || '広域'} / #{item[:genre] || '未判定'} / CV意図=#{item[:cv_intent]}",
          "供給=DB店舗#{item[:shops_count]} / 確認済み#{item[:confirmed_count]} / 記事#{item[:articles_count]}",
          "期待値=#{item[:expected_score]} / ROI=#{item[:roi_score]} / 作業コスト=#{item[:work_label]}",
          "TODO=#{item[:todo].join(' / ')}"
        ].join("\n")
      end

      def execution_prompt_for(item)
        return nil if action_type_for(item) == "new_article_candidate"

        <<~TEXT.strip
          AICOO Action 作業メモ

          今日やること:
          #{item[:concrete_task]}

          根拠:
          #{evaluation_reason_for(item)}

          実行手順:
          #{item[:todo].map.with_index(1) { |line, index| "#{index}. #{line}" }.join("\n")}
        TEXT
      end

      def concrete_task_for(item)
        case item[:work_type]
        when "search_intent_analysis"
          return "「#{item[:query]}」の検索意図と対応ページ要件を確認する"
        when "competitor_analysis"
          return "「#{item[:query]}」の競合要素を確認し、自社ページ要件を整理する"
        when "data_shortage"
          return "「#{item[:query]}」の改善判断に必要なGSC/GA4/内部データを確認する"
        when "new_article"
          return "「#{item[:query]}」向けの新規記事候補を作成する"
        when "new_lp"
          return "「#{item[:query]}」向けのLPを1ページ作成する"
        when "new_category"
          return "#{item[:area] || item[:genre] || item[:query]}向けのカテゴリページを1ページ作成する"
        end

        case item[:recommended_action]
        when "CTR改善優先"
          "#{item[:query]}のSEOタイトル/meta descriptionを改善する"
        when "あと少し改善優先"
          "#{item[:query]}のtitle/metaを改善し、関連ページから内部リンクを3本追加する"
        when "店舗追加優先"
          "#{item[:area] || '対象エリア'}の#{item[:genre] || '対象ジャンル'}店舗を#{target_amount_for(item)}件追加する"
        when "記事追加優先"
          "「#{article_ideas_for(item).first || item[:query]}」の記事を1本作成する"
        when "内部リンク・導線改善"
          "#{item[:landing_page].presence || item[:query]}に店舗カードCTAと関連記事リンクを追加する"
        else
          if item[:confirmed_count].to_i < 10 && item[:shops_count].to_i.positive?
            "#{item[:area] || '対象エリア'}の#{item[:genre] || '対象ジャンル'}店舗を15件電話確認する"
          else
            "#{item[:query]}に関連する内部リンクを3本追加する"
          end
        end
      end

      def todo_lines_for(item)
        return search_intent_analysis_todo_lines_for(item) if item[:work_type] == "search_intent_analysis"
        return competitor_analysis_todo_lines_for(item) if item[:work_type] == "competitor_analysis"
        return data_shortage_todo_lines_for(item) if item[:work_type] == "data_shortage"
        return new_page_todo_lines_for(item) unless item[:page_exists]

        lines = []
        case item[:strategy]
        when "既存記事改善"
          lines << "既存LPを改善する: #{item[:landing_page]}"
          lines << "title/meta/冒頭を検索意図に寄せる"
          lines << "関連記事リンクと店舗カード導線を強化する"
        when "地域特化記事を新規作成"
          lines << "#{item[:local_area]}特化記事を新規作成する"
        when "テーマ特化記事を新規作成"
          lines << "#{item[:theme]}特化記事を新規作成する"
        end

        case item[:recommended_action]
        when "CTR改善優先"
          lines << "SEOタイトルを喫煙意図に寄せて改善する"
          lines << "meta descriptionに「席で吸える」「紙タバコ」などを入れる"
        when "あと少し改善優先"
          lines << "該当LPのtitle/metaを検索意図に寄せて改善する"
          lines << "関連する記事・エリアページ・店舗ページから内部リンクを追加する"
          lines << "記事冒頭に結論店舗カードや条件リンクを追加する"
        when "店舗追加優先"
          lines << "#{item[:area] || '対象エリア'}の#{item[:genre] || '対象ジャンル'}店舗を+#{target_amount_for(item)}件追加する"
          lines << "#{item[:area] || '対象エリア'}の#{item[:genre] || '対象ジャンル'}店舗を優先的に電話確認する"
        when "記事追加優先"
          article_ideas_for(item).first(2).each { |idea| lines << "記事作成：#{idea}" }
          lines << "既存記事から関連記事リンクを追加する"
        when "内部リンク・導線改善"
          lines << "記事冒頭に結論店舗カードを追加する"
          lines << "関連記事・店舗ページへの内部リンクを増やす"
        else
          lines << "該当ページを確認して小さく改善する"
        end
        lines.uniq
      end

      def target_amount_for(item)
        if item[:recommended_action] == "店舗追加優先"
          return 30 if item[:shops_count].to_i < 10
          return 20 if item[:shops_count].to_i < 30
          return 10
        end
        item[:recommended_action] == "あと少し改善優先" ? 3 : 1
      end

      def action_type_for(item)
        case item[:work_type]
        when "search_intent_analysis" then return "opportunity_validation"
        when "competitor_analysis" then return "market_research"
        when "data_shortage" then return "data_preparation"
        when "new_article" then return "new_article_candidate"
        when "new_category" then return "seo_article"
        when "new_lp" then return "build_lp"
        end

        case item[:recommended_action]
        when "店舗追加優先" then "data_preparation"
        when "内部リンク・導線改善" then "ui_improvement"
        when "CTR改善優先", "あと少し改善優先" then "seo_improvement"
        else "seo_article"
        end
      end

      def execution_mode_for(item)
        case item[:work_type]
        when "search_intent_analysis", "competitor_analysis" then return "manual_operation"
        when "data_shortage" then return "data_operation"
        when "new_article", "new_lp", "new_category" then return "content_creation"
        end

        case item[:recommended_action]
        when "店舗追加優先" then "data_operation"
        when "CTR改善優先", "あと少し改善優先", "記事追加優先" then "content_creation"
        when "内部リンク・導線改善" then "code_revision"
        else "manual_operation"
        end
      end

      def status_for(item)
        action_type_for(item) == "new_article_candidate" ? "proposal" : "idea"
      end

      def expected_value_yen_for(item)
        [ (item[:expected_score].to_f * 120).round, 3_000 ].max
      end

      def success_probability_for(item)
        case item[:recommended_action]
        when "店舗追加優先" then 0.55
        when "CTR改善優先" then 0.42
        when "あと少し改善優先" then 0.36
        when "内部リンク・導線改善" then 0.4
        else 0.34
        end
      end

      def detect_area(query)
        normalized = query.to_s.downcase
        AREA_KEYWORDS.each { |area, keywords| return area if keywords.any? { |keyword| normalized.include?(keyword.downcase) } }
        nil
      end

      def detect_local_area(query)
        normalized = query.to_s.downcase
        LOCAL_AREA_KEYWORDS.each { |area, keywords| return area if keywords.any? { |keyword| normalized.include?(keyword.downcase) } }
        nil
      end

      def detect_genre(query)
        normalized = query.to_s.downcase
        GENRE_KEYWORDS.each { |genre, keywords| return genre if keywords.any? { |keyword| normalized.include?(keyword.downcase) } }
        nil
      end

      def detect_theme(query:, landing_page: nil)
        text = [ query, landing_page ].compact.join(" ").downcase
        return "デート" if text.match?(/デート|横並び|記念日|雰囲気|2人|二人|yokonarabi|date/)
        return "シーシャ" if text.match?(/シーシャ|shisha|hookah/)
        return "個室" if text.match?(/個室|private-room/)
        return "バー" if text.match?(/バー|bar/)
        return "居酒屋" if text.match?(/居酒屋|izakaya/)
        return "喫煙所" if text.match?(/喫煙所|喫煙スペース|喫煙室/)

        nil
      end

      def detect_cv_intent(query)
        normalized = query.to_s.downcase
        return "high" if CV_INTENT_KEYWORDS[:high].any? { |keyword| normalized.include?(keyword.downcase) }
        return "medium" if CV_INTENT_KEYWORDS[:medium].any? { |keyword| normalized.include?(keyword.downcase) }
        return "low" if CV_INTENT_KEYWORDS[:low].any? { |keyword| normalized.include?(keyword.downcase) }

        "unknown"
      end

      def detect_query_type(query)
        normalized = query.to_s.downcase.strip
        return "facility_smoking" if FACILITY_SMOKING_KEYWORDS.any? { |keyword| normalized.include?(keyword.downcase) }
        return "specific_shop" if normalized.match?(/[&×]/) && !normalized.include?("喫煙")

        "general_seo"
      end

      def position_multiplier(position)
        case position.to_f
        when 1..3 then 0.6
        when 4..7 then 1.0
        when 8..20 then 1.6
        when 21..50 then 1.2
        else 0.7
        end
      end

      def ctr_multiplier(ctr_percent)
        case ctr_percent.to_f
        when 0...1 then 1.6
        when 1...3 then 1.3
        when 3...8 then 1.0
        else 0.7
        end
      end

      def cv_intent_multiplier(cv_intent)
        { "high" => 1.4, "medium" => 1.15, "low" => 0.7 }.fetch(cv_intent.to_s, 1.0)
      end

      def expected_impact_score(impressions:, position:, ctr_percent:, supply_score:, revenue_fit:, cv_intent:)
        ranking_boost = case position.to_f
        when 1..3 then 0.8
        when 4..10 then 1.6
        when 11..20 then 2.0
        when 21..50 then 1.4
        else 0.8
        end
        ctr_boost = case ctr_percent.to_f
        when 0...1 then 2.0
        when 1...3 then 1.6
        when 3...8 then 1.2
        else 0.8
        end
        shortage_boost = supply_score <= 20 ? 2.0 : (supply_score <= 60 ? 1.5 : 1.0)
        (impressions.to_f * ranking_boost * ctr_boost * shortage_boost * revenue_fit.to_f * cv_intent_multiplier(cv_intent)).round(1)
      end

      def ga4_value_score(data)
        views = data[:views].to_i
        active_users = data[:active_users].to_i
        engagement_seconds = data[:engagement_seconds].to_f
        events = data[:events].to_i
        return 0 if views <= 0 && active_users <= 0 && events <= 0

        engagement_score = case engagement_seconds
        when 0...10 then 0.5
        when 10...30 then 1.0
        when 30...90 then 1.5
        else 2.0
        end
        event_score = active_users.positive? ? events.to_f / active_users : events.to_f
        (views.to_f + (active_users * 3) + (event_score * 5) + (engagement_score * 20)).round(1)
      end

      def theme_multiplier(theme)
        { "デート" => 1.7, "シーシャ" => 1.8, "個室" => 1.35, "バー" => 1.3, "深夜" => 1.25, "居酒屋" => 1.1, "喫煙所" => 0.45 }.fetch(theme.to_s, 1.0)
      end

      def total_opportunity_score(expected_score:, ga4_score:, theme:)
        ((expected_score.to_f + (ga4_score.to_f * 1.8)) * theme_multiplier(theme)).round(1)
      end

      def next_move_score_for(item)
        cv_boost = { "high" => 1.35, "medium" => 1.15 }.fetch(item[:cv_intent].to_s, 1.0)
        strategy_boost = case item[:strategy].to_s
        when "既存記事改善" then 1.25
        when "地域特化記事を新規作成" then 1.2
        when "テーマ特化記事を新規作成" then 1.15
        else 1.0
        end
        ((item[:expected_score].to_f * 0.45) + (item[:ga4_score].to_f * 0.35) + (item[:roi_score].to_f * 0.2)) * cv_boost * strategy_boost
      end

      def work_cost_for(action)
        {
          "CTR改善優先" => 1.0,
          "あと少し改善優先" => 1.2,
          "内部リンク・導線改善" => 1.5,
          "記事追加優先" => 3.0,
          "店舗追加優先" => 5.0
        }.fetch(action.to_s, 2.0)
      end

      def roi_score_for(expected_score:, action:)
        (expected_score.to_f / work_cost_for(action)).round(1)
      end

      def work_label_for(action)
        {
          "CTR改善優先" => "低：title/meta改善中心",
          "あと少し改善優先" => "低〜中：タイトル・内部リンク・導線調整",
          "内部リンク・導線改善" => "低〜中：内部リンク・CTA調整",
          "記事追加優先" => "中：記事作成",
          "店舗追加優先" => "高：店舗収集・確認"
        }.fetch(action.to_s, "中：確認作業")
      end

      def recommended_action_for(position:, impressions:, ctr_percent:, shops_count:, articles_count:, ga4_data:)
        return "あと少し改善優先" if position >= 8 && position <= 20 && impressions >= 30
        return "CTR改善優先" if position <= 10 && ctr_percent < 1.5
        return "店舗追加優先" if shops_count <= 15
        return "記事追加優先" if articles_count <= 1
        return "内部リンク・導線改善" if ga4_data[:views].to_i > 0 && ga4_data[:engagement_seconds].to_f < 15

        "維持・微改善"
      end

      def article_strategy_for(query_type:, specific_shop_query:, landing_page:, position:, ctr_percent:, articles_count:, article_relevance_score:, local_area:, theme:)
        return "不要" if query_type != "general_seo" || specific_shop_query
        has_strong_article = article_relevance_score.to_i >= 70
        return "既存記事改善" if landing_page.present? && has_strong_article && position.to_f <= 15 && ctr_percent.to_f < 2.0
        return "地域特化記事を新規作成" if local_area.present? && !has_strong_article
        return "テーマ特化記事を新規作成" if theme.present? && !has_strong_article && articles_count.to_i <= 1
        return "既存記事改善" if landing_page.present? && has_strong_article

        "新規記事作成"
      end

      def strategy_reason_for(strategy:, position:, ctr_percent:, article_relevance_score:, local_area:, theme:)
        case strategy
        when "既存記事改善" then "順位#{position}位 / CTR#{ctr_percent}% / 記事関連度#{article_relevance_score}"
        when "地域特化記事を新規作成" then "#{local_area || '地域'} / 専用記事不足 / 記事関連度#{article_relevance_score}"
        when "テーマ特化記事を新規作成" then "#{theme || 'テーマ'} / 専用記事不足 / 記事関連度#{article_relevance_score}"
        else "専用LP不足"
        end
      end

      def next_move_type_for(item)
        return "既存記事CTR改善" if item[:strategy].to_s == "既存記事改善" && item[:ctr_percent].to_f < 2.0
        return "新規記事作成" if item[:strategy].to_s.include?("新規作成")
        return "回遊・世界観強化" if item[:ga4_score].to_f >= 100 && item[:theme].present?
        return "確認済み店舗強化" if item[:confirmed_count].to_i < 10 && item[:shops_count].to_i.positive?
        return "内部リンク・CTA改善" if item[:recommended_action].to_s == "内部リンク・導線改善"

        item[:recommended_action].presence || "維持・微改善"
      end

      def article_ideas_for(item)
        area = item[:area]
        genre = item[:genre]
        return [] if area.blank? || genre.blank?

        [
          "#{area}で喫煙できる#{genre}まとめ",
          "#{area}で紙タバコが吸える#{genre}",
          "#{area}で深夜営業している喫煙#{genre}",
          "#{area}でデート向けの喫煙可能#{genre}",
          "#{area}でコスパがいい喫煙#{genre}"
        ].uniq
      end

      def shop_count_for(area:, local_area:, genre:)
        matching_activity_count(resource_types: %w[Shop Listing], area:, local_area:, genre:)
      end

      def confirmed_shop_count_for(area:, local_area:, genre:)
        matching_activity_count(resource_types: %w[Shop Listing], area:, local_area:, genre:, confirmed_only: true)
      end

      def article_relevance_for(query:, area:, local_area:, genre:, theme:)
        logs = business.business_activity_logs.where(resource_type: "Article")
        candidates = logs.map do |log|
          text = activity_text(log).downcase
          score = 0
          score += 35 if local_area.present? && text.include?(local_area.to_s.downcase)
          score += 25 if area.present? && text.include?(area.to_s.downcase)
          score += 25 if genre.present? && text.include?(genre.to_s.downcase)
          score += 20 if theme.present? && text.include?(theme.to_s.downcase)
          query.to_s.downcase.split(/[ 　]/).each { |word| score += 5 if word.length > 1 && text.include?(word) }
          next if score.zero?

          { path: article_path_for(log), title: log.title, score: }
        end.compact
        best = candidates.max_by { |candidate| candidate[:score] }
        { count: candidates.count, best_score: best ? best[:score] : 0, best_path: best ? best[:path] : "", best_title: best ? best[:title] : "" }
      end

      def matching_activity_count(resource_types:, area:, local_area:, genre:, confirmed_only: false)
        logs = business.business_activity_logs.where(resource_type: resource_types).limit(5_000)
        terms = [ area, local_area, genre, *(GENRE_DB_GROUPS[genre] || []) ].compact_blank.map(&:downcase)
        logs.count do |log|
          text = activity_text(log).downcase
          matches_terms = terms.empty? || terms.any? { |term| text.include?(term) }
          matches_confirmed = !confirmed_only || log.activity_type.to_s.include?("verified") || text.include?("確認済")
          matches_terms && matches_confirmed
        end
      end

      def activity_text(log)
        [
          log.title,
          log.diff_summary,
          log.metadata,
          log.before_snapshot,
          log.after_snapshot,
          log.changed_fields
        ].compact.join(" ")
      end

      def article_path_for(log)
        slug = log.metadata.to_h["slug"].presence || log.after_snapshot.to_h["slug"].presence || log.resource_id
        slug.to_s.start_with?("/") ? slug.to_s : "/articles/#{slug}"
      end

      def page_match_for(query:, raw_landing_page:, gsc_landing_page_present:, target_url:, articles:)
        owned_raw = Aicoo::BusinessOwnedUrlPolicy.call(business:, url: raw_landing_page)
        if gsc_landing_page_present && raw_landing_page.present? && owned_raw.owner_page? && owned_raw.reference_url.blank? && !generic_home_page?(owned_raw.url, query)
          return {
            page_exists: true,
            matched_page: target_url.url,
            recommended_slug: nil,
            creation_type: "existing_page_improvement",
            work_type: "existing_page_improvement"
          }
        end

        if articles[:best_score].to_i >= 70 && articles[:best_path].present?
          return {
            page_exists: true,
            matched_page: articles[:best_path],
            recommended_slug: nil,
            creation_type: "existing_page_improvement",
            work_type: "existing_page_improvement"
          }
        end

        work_type = missing_page_work_type_for(query)

        {
          page_exists: false,
          matched_page: nil,
          recommended_slug: recommended_slug_for(query),
          creation_type: work_type,
          work_type:
        }
      end

      def recommended_slug_for(query)
        normalized = query.to_s.downcase
        return "suelog-vs-tabelog" if normalized.include?(business.name.to_s.downcase) && query.to_s.include?("比較")

        parameterized = query.to_s.parameterize
        parameterized.presence || "article-#{Digest::SHA1.hexdigest(query.to_s).first(10)}"
      end

      def generic_home_page?(url, query)
        path = URI.parse(url.to_s).path.presence || "/"
        path == "/" && query.to_s.squish != business.name.to_s.squish
      rescue URI::InvalidURIError
        false
      end

      def missing_page_work_type_for(query)
        return "new_article" if new_article_candidate_query?(query)
        return "search_intent_analysis" if ambiguous_search_intent?(query)

        text = query.to_s
        return "new_lp" if text.match?(/料金|価格|問い合わせ|登録|申し込み/)
        return "new_category" if detect_area(text).present? || detect_genre(text).present?

        "new_article"
      end

      def new_article_candidate_query?(query)
        text = query.to_s.squish
        normalized = text.downcase
        business_name = business.name.to_s.downcase
        branded_query = business_name.present? && normalized.include?(business_name)
        return true if branded_query && text.match?(/比較|とは|違い|評判|口コミ|おすすめ|使い方|サービス/)

        detect_area(text).present? || detect_local_area(text).present? || detect_genre(text).present? || detect_theme(query: text).present?
      end

      def ambiguous_search_intent?(query)
        text = query.to_s.squish
        normalized = text.downcase
        business_name = business.name.to_s.downcase
        branded_query = business_name.present? && normalized.include?(business_name)
        brand_discovery_terms = /比較|とは|違い|評判|口コミ|おすすめ|使い方|サービス/
        has_specific_target = detect_area(text).present? || detect_local_area(text).present? || detect_genre(text).present? || detect_theme(query: text).present?

        return true if branded_query && text.match?(brand_discovery_terms) && !has_specific_target
        return true if !has_specific_target && detect_cv_intent(text) == "unknown"

        false
      end

      def new_page_todo_lines_for(item)
        return new_article_candidate_todo_lines_for(item) if item[:work_type] == "new_article"

        [
          "新規作成: #{item[:work_type]} / slug=#{item[:recommended_slug]}",
          "検索意図「#{item[:query]}」に対応するタイトル・構成を決める",
          "既存の#{business.name}ページから内部リンクを追加する",
          "公開後、ActionResult登録用にURLと狙いKWをメモする"
        ]
      end

      def new_article_candidate_todo_lines_for(item)
        article = article_candidate_metadata_for(item)
        [
          "記事企画を確認する: #{article.fetch('recommended_title')}",
          "推奨URLを確認する: /articles/#{article.fetch('recommended_url_slug')}",
          "必要データを揃える: #{article.fetch('required_data').join(' / ')}",
          "記事作成を進める場合だけ承認し、承認後にCodex Promptを生成する"
        ]
      end

      def article_candidate_metadata_for(item)
        return unless item[:work_type] == "new_article"

        {
          "search_query" => item[:query],
          "search_intent" => search_intent_for(item),
          "recommended_title" => recommended_article_title_for(item),
          "recommended_url_slug" => item[:recommended_slug],
          "recommended_url" => "/articles/#{item[:recommended_slug]}",
          "article_summary" => article_summary_for(item),
          "article_reason" => article_reason_for(item),
          "article_outline" => article_outline_for(item),
          "required_data" => required_article_data_for(item),
          "expected_pv" => expected_pv_for(item),
          "expected_ctr_lift" => expected_ctr_lift_for(item),
          "expected_profit_yen" => expected_value_yen_for(item),
          "priority" => item[:next_move_score]
        }
      end

      def search_intent_for(item)
        query = item[:query].to_s
        return "比較したい" if query.match?(/比較|違い|vs|VS/)
        return "評判や口コミを確認したい" if query.match?(/評判|口コミ|レビュー/)
        return "サービス内容を知りたい" if query.match?(/とは|使い方|サービス/)
        return "喫煙できる店を探したい" if item[:area].present? || item[:genre].present? || item[:theme].present?

        "検索意図を確認したい"
      end

      def recommended_article_title_for(item)
        query = item[:query].to_s
        if query.include?(business.name.to_s) && query.include?("比較")
          return "#{business.name}と食べログを比較｜喫煙できる飲食店を探すならどっち？"
        end

        "「#{query}」で探す人向けの#{business.name}活用ガイド"
      end

      def article_summary_for(item)
        if item[:query].to_s.include?(business.name.to_s) && item[:query].to_s.include?("比較")
          return "#{business.name}と主要グルメサイトを比較し、喫煙可能店舗検索という観点で違いを解説する。"
        end

        "検索クエリ「#{item[:query]}」の意図に合わせて、#{business.name}内で探せる条件・使い方・関連ページへの導線を整理する。"
      end

      def article_reason_for(item)
        "GSCで検索需要がありますが、対応ページが存在しないため。表示#{item[:impressions]}・CTR#{item[:ctr_percent]}%・順位#{item[:position]}を改善する受け皿が必要です。"
      end

      def article_outline_for(item)
        if item[:query].to_s.include?(business.name.to_s) && item[:query].to_s.include?("比較")
          return [
            "H1 #{business.name}と食べログを徹底比較",
            "H2 #{business.name}とは",
            "H2 食べログとの違い",
            "H2 喫煙可能店舗検索で比較",
            "H2 メリット・デメリット",
            "H2 どんな人におすすめか"
          ]
        end

        [
          "H1 #{recommended_article_title_for(item)}",
          "H2 検索している人の悩み",
          "H2 #{business.name}で確認できること",
          "H2 関連する条件・エリア",
          "H2 よくある質問",
          "H2 次に見るページ"
        ]
      end

      def required_article_data_for(item)
        [
          "比較対象",
          item[:area].present? ? "#{item[:area]}の関連店舗数" : "必要店舗数",
          "必要画像",
          "内部リンク先",
          "確認事項"
        ].compact
      end

      def expected_pv_for(item)
        [ (item[:impressions].to_i * 0.08).round, 20 ].max
      end

      def expected_ctr_lift_for(item)
        current = item[:ctr_percent].to_f
        target = current < 3 ? 3.0 : (current + 0.8)
        "#{current.round(1)}% -> #{target.round(1)}%"
      end

      def search_intent_analysis_todo_lines_for(item)
        [
          "GSCで「#{item[:query]}」の表示回数・クリック・現在の流入先を確認する",
          "#{business.name}内に対応ページがあるか確認する",
          "SERPは参考として上位ページの意図を分類する",
          "既存改善・新規記事・新規LP・新規カテゴリのどれにするか判断する",
          "次のActionCandidate用に判断理由と推奨URL/slugをメモする"
        ]
      end

      def competitor_analysis_todo_lines_for(item)
        [
          "参考競合URLを確認し、共通要素を3つ抽出する",
          "#{business.name}に不足している要素を整理する",
          "改善対象は必ず#{business.production_url.presence || '自社URL'}配下から選ぶ",
          "次のActionCandidate用に改善要件をメモする"
        ]
      end

      def data_shortage_todo_lines_for(item)
        [
          "GSC/GA4/内部ログの不足項目を確認する",
          "改善対象ページを特定できるデータがあるか確認する",
          "不足している計測・紐付けをメモする"
        ]
      end

      def owned_target_url_for(raw_url, area:, local_area:, genre:, theme:)
        Aicoo::BusinessOwnedUrlPolicy.call(
          business:,
          url: raw_url,
          fallback: infer_landing_page(area:, local_area:, genre:, theme:).presence || "https://suelog.jp/"
        )
      end

      def infer_landing_page(area:, local_area:, genre:, theme:)
        return "/articles/#{local_area.parameterize}-smoking" if local_area.present?
        return "/umeda/genre/bar" if area == "梅田" && genre == "バー"
        return "/umeda/genre/izakaya" if area == "梅田" && genre == "居酒屋"
        return "/umeda" if area == "梅田"
        return "/namba" if area == "難波"
        return "/nishinakajima" if area == "西中島"
        return "/honmachi" if area == "本町"
        return "/articles/#{theme.parameterize}-smoking" if theme.present?

        ""
      end

      def ga4_data_for(_landing_page)
        {
          views: recent_pageviews,
          active_users: recent_users,
          engagement_seconds: recent_average_engagement_seconds,
          events: recent_event_count
        }
      end

      def recent_metrics
        @recent_metrics ||= business.business_metric_dailies.where(recorded_on: (today - 29)..today).to_a
      end

      def recent_impressions = recent_metrics.sum { |metric| metric.impressions.to_i }
      def recent_clicks = recent_metrics.sum { |metric| metric.clicks.to_i }
      def recent_pageviews = recent_metrics.sum { |metric| metric.pageviews.to_i }
      def recent_users = recent_metrics.sum { |metric| metric.users.to_i }
      def recent_event_count = recent_metrics.sum { |metric| metric.event_count.to_i + metric.phone_clicks.to_i + metric.map_clicks.to_i + metric.affiliate_clicks.to_i }

      def recent_average_engagement_seconds
        values = recent_metrics.filter_map { |metric| metric.average_engagement_time_seconds.to_d if metric.average_engagement_time_seconds.to_d.positive? }
        return 0 if values.empty?

        (values.sum / values.size).round(1)
      end

      def recent_ctr_percent
        return 0 if recent_impressions.zero?

        ((recent_clicks.to_d / recent_impressions) * 100).round(2)
      end

      def recent_position
        values = recent_metrics.filter_map { |metric| metric.average_position.to_d if metric.average_position.to_d.positive? }
        return 12 if values.empty?

        (values.sum / values.size).round(1)
      end

      def latest_gsc_imports
        @latest_gsc_imports ||= business.data_sources
          .where(source_type: "gsc")
          .includes(:data_imports)
          .flat_map { |source| source.data_imports.recent.limit(3).to_a }
          .sort_by { |data_import| [ data_import.imported_at || Time.zone.at(0), data_import.created_at || Time.zone.at(0) ] }
          .reverse
          .first(3)
      end

      def rows_from_gsc_import(data_import)
        rows = rows_from_gsc_processed_text(data_import.processed_text)
        rows = rows_from_gsc_raw_text(data_import.raw_text) if rows.empty?
        rows
      end

      def rows_from_gsc_processed_text(processed_text)
        return [] if processed_text.blank?

        CSV.parse(processed_text, headers: true).filter_map do |row|
          query = value_from_row(row, "query", "検索クエリ", "keyword")
          next if query.blank?

          {
            query:,
            impressions: numeric_value(value_from_row(row, "impressions", "表示回数")),
            clicks: numeric_value(value_from_row(row, "clicks", "クリック数")),
            ctr_percent: ctr_percent_value(value_from_row(row, "ctr", "CTR")),
            position: numeric_value(value_from_row(row, "position", "掲載順位", "平均掲載順位")),
            landing_page: value_from_row(row, "page", "ページ", "url"),
            source: "gsc_data_import"
          }
        end
      rescue CSV::MalformedCSVError
        []
      end

      def rows_from_gsc_raw_text(raw_text)
        return [] if raw_text.blank?

        parsed = JSON.parse(raw_text)
        Array(parsed["rows"]).filter_map do |row|
          query = Array(row["keys"]).first.presence || row["query"].presence
          next if query.blank?

          impressions = numeric_value(row["impressions"])
          clicks = numeric_value(row["clicks"])
          {
            query:,
            impressions:,
            clicks:,
            ctr_percent: ctr_percent_value(row["ctr"]),
            position: numeric_value(row["position"]),
            source: "gsc_raw_import"
          }
        end
      rescue JSON::ParserError
        []
      end

      def value_from_row(row, *keys)
        keys.lazy.map { |key| row[key] || row[key.to_s] || row[key.to_sym] }.find(&:present?)
      end

      def numeric_value(value)
        value.to_s.delete(",").to_d
      end

      def ctr_percent_value(value)
        numeric = numeric_value(value)
        numeric <= 1 ? (numeric * 100) : numeric
      end

      def serp_reference_for(query)
        return nil unless serp_allowed?

        analysis = business.serp_analyses
          .successful
          .where(keyword: query)
          .order(analyzed_at: :desc, created_at: :desc)
          .first
        return nil unless analysis

        {
          "role" => "reference_only",
          "keyword" => analysis.keyword,
          "analysis_id" => analysis.id,
          "top_results" => analysis.serp_results.order(position: :asc).limit(5).map do |result|
            {
              "position" => result.position,
              "title" => result.title,
              "url" => result.url,
              "snippet" => result.snippet
            }.compact
          end
        }
      end
    end
  end
end
