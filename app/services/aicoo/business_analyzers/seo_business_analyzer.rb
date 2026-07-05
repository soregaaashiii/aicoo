module Aicoo
  module BusinessAnalyzers
    class SeoBusinessAnalyzer < BaseAnalyzer
      SEO_MEDIA_TYPES = %w[seo_media content_media directory].freeze
      DEFAULT_AREA_KEYWORDS = [
        "梅田 喫煙 居酒屋",
        "難波 喫煙 カフェ",
        "大阪 喫煙可能 飲食店"
      ].freeze

      private

      def handled_business_type?
        business.business_type.in?(SEO_MEDIA_TYPES)
      end

      def issues
        [
          low_ctr_issue,
          rank_opportunity_issue,
          conversion_path_issue,
          internal_link_issue,
          content_gap_issue,
          shop_data_issue,
          verified_shop_issue
        ].compact
      end

      def low_ctr_issue
        return if recent_impressions.zero?

        ctr = recent_ctr
        return unless ctr < 0.02

        target_count = [ (recent_impressions / 200.0).ceil, 3 ].max
        target_count = [ target_count, 8 ].min
        query = primary_query || "表示回数がある検索クエリ"

        issue(
          key: "seo_low_ctr_titles",
          title: "CTR#{percent(ctr)}の検索入口を#{target_count}件書き換える",
          description: "#{business.name}で表示回数はありますがCTRが#{percent(ctr)}です。検索結果上でクリックされるタイトル/metaへ更新します。",
          action_type: "seo_improvement",
          quantity: target_count,
          unit: "件",
          why: "直近7日のGSC集計でimpressions=#{recent_impressions}、clicks=#{recent_clicks}、CTR=#{percent(ctr)}です。検索需要に対してクリック獲得が弱い状態です。",
          expected_effect: "CTR +0.8pt、月間クリック +#{estimated_click_lift(target_count)}、期待利益 +#{yen_label(estimated_value(24_000))}",
          expected_value_yen: estimated_value(24_000),
          success_probability: 0.42,
          strategic_value_score: 58,
          risk_reduction_score: 28,
          expected_hours: 1.5,
          metadata: {
            "evidence_sources" => [ "gsc" ],
            "source_query" => query,
            "source_metric" => "gsc_ctr",
            "current_value" => ctr.to_f,
            "benchmark_value" => 0.03,
            "current_title" => "#{business.name}｜#{query}",
            "proposed_title" => "【#{Date.current.year}年版】#{query}｜#{business.name}",
            "current_meta_description" => "検索結果でクリック理由が弱い状態です。",
            "proposed_meta_description" => "#{query}を探す人向けに、喫煙可否・エリア・利用シーンを整理。#{business.name}で条件に合うお店をすぐ確認できます。",
            "expected_ctr_delta" => "+0.8pt",
            "expected_rank_delta" => "維持〜+1.0位",
            "candidate_pages" => candidate_pages_for_seo
          }
        )
      end

      def rank_opportunity_issue
        analysis = latest_serp_analysis
        return unless analysis&.successful?
        return if analysis.competition_score.to_i < 55

        query = analysis.keyword
        return if query.blank?

        target = branded_gap?(analysis) ? "指名検索対策記事を1本作成する" : "「#{query}」の上位との差分を1ページで埋める"
        slug = query_slug(query)

        issue(
          key: "seo_rank_11_20_gap",
          title: target,
          description: "#{query} のSERP上位に対して、比較表・FAQ・内部リンク・CTAの不足を埋めます。",
          action_type: "seo_article",
          quantity: 1,
          unit: "本",
          why: "SERP competition_score=#{analysis.competition_score}、上位#{relevant_serp_count(analysis)}件がBusiness領域に関連しています。順位11〜20位相当の改善余地として扱います。",
          expected_effect: "平均順位 +2.0位、CTR +0.6pt、期待利益 +#{yen_label(estimated_value(22_000))}",
          expected_value_yen: estimated_value(22_000),
          success_probability: 0.36,
          strategic_value_score: 62,
          risk_reduction_score: 34,
          expected_hours: 2,
          metadata: {
            "evidence_sources" => [ "serp", "gsc" ],
            "source_query" => query,
            "serp_analysis_id" => analysis.id,
            "current_value" => analysis.competition_score.to_i,
            "benchmark_value" => 55,
            "serp_top_results" => serp_rows(analysis),
            "serp_common_words" => serp_common_words(analysis),
            "recommended_slug" => slug,
            "recommended_title" => "#{query}の比較・選び方｜#{business.name}",
            "proposed_h1" => "#{query}の比較・選び方",
            "proposed_title" => "【#{Date.current.year}年版】#{query}の比較・選び方｜#{business.name}",
            "proposed_meta_description" => "#{query}を探す人向けに、喫煙可否・エリア・掲載数・使い方を比較。#{business.name}で条件に合うお店を確認できます。",
            "candidate_pages" => candidate_pages_for_query(query),
            "expected_ctr_delta" => "+0.6pt",
            "expected_rank_delta" => "+2.0位"
          }
        )
      end

      def conversion_path_issue
        return unless recent_clicks.positive? || recent_pageviews.positive?
        return if recent_conversion_clicks.positive? || recent_conversions.positive?

        target_count = [ (recent_pageviews / 100.0).ceil, 5 ].max
        target_count = [ target_count, 10 ].min

        issue(
          key: "seo_conversion_path_zero",
          title: "電話・地図・アフィリエイト導線を#{target_count}ページに追加する",
          description: "#{business.name}で流入はありますが、電話/地図/アフィリエイトクリックが0です。店舗詳細・地図・記事内店舗カードに送客導線を追加します。",
          action_type: "ui_improvement",
          quantity: target_count,
          unit: "ページ",
          why: "直近7日にclicks=#{recent_clicks}, pageviews=#{recent_pageviews}がありますが、phone/map/affiliate_clicksが0です。",
          expected_effect: "送客クリック +#{target_count * 3}/週、期待利益 +#{yen_label(estimated_value(35_000))}",
          expected_value_yen: estimated_value(35_000),
          success_probability: 0.4,
          strategic_value_score: 60,
          risk_reduction_score: 32,
          expected_hours: 2,
          metadata: {
            "evidence_sources" => [ "gsc", "ga4", "business_db" ],
            "source_metric" => "phone_map_affiliate_clicks",
            "current_value" => recent_conversion_clicks,
            "benchmark_value" => 1,
            "candidate_pages" => [ "店舗詳細ページ", "地図ページ", "記事内店舗カード" ],
            "current_cta" => "店舗カード内の電話・地図・予約/アフィリエイト導線が弱い、または未計測です。",
            "proposed_cta" => "電話する / 地図で見る / 予約・詳細を見る を店舗カード上部と本文末に表示し、クリックイベントを記録する。",
            "target_files" => [
              "app/views/shops/show.html.erb",
              "app/views/articles/show.html.erb",
              "app/javascript/controllers/conversion_tracking_controller.js"
            ],
            "completion_criteria" => [
              "店舗詳細ページに電話・地図・予約/アフィリエイト導線が表示されている",
              "記事内店舗カードに同じ送客導線が表示されている",
              "phone_clicks / map_clicks / affiliate_clicks のイベントが記録される",
              "ActionResult登録用の変更メモが生成される"
            ],
            "expected_ctr_delta" => "送客クリック +#{target_count * 3}/週",
            "expected_rank_delta" => "順位影響なし"
          }
        )
      end

      def internal_link_issue
        return unless recent_sessions.positive?
        return if recent_views_per_session > 1.3

        link_count = [ (recent_sessions / 20.0).ceil * 3, 15 ].max
        link_count = [ link_count, 30 ].min

        issue(
          key: "seo_internal_links_shortage",
          title: "流入ページから内部リンクを#{link_count}件追加する",
          description: "#{business.name}のViews/Sessionが#{recent_views_per_session.round(2)}です。エリア・カテゴリ・店舗詳細への内部リンクを増やして回遊を作ります。",
          action_type: "seo_improvement",
          quantity: link_count,
          unit: "件",
          why: "直近7日のsessions=#{recent_sessions}、pageviews=#{recent_pageviews}で、回遊が弱い状態です。",
          expected_effect: "Views/Session +0.3、送客クリック +#{[ link_count / 5, 3 ].max}/週",
          expected_value_yen: estimated_value(18_000),
          success_probability: 0.39,
          strategic_value_score: 54,
          risk_reduction_score: 25,
          expected_hours: 1.5,
          metadata: {
            "evidence_sources" => [ "ga4", "business_db" ],
            "source_metric" => "views_per_session",
            "current_value" => recent_views_per_session.to_f,
            "benchmark_value" => 1.3,
            "candidate_pages" => [ "流入上位記事", "エリア一覧ページ", "カテゴリ一覧ページ" ],
            "current_internal_links" => "関連記事・近隣エリア・店舗詳細へのリンクが不足しています。",
            "proposed_internal_links" => "大阪、梅田、難波、喫煙可能カフェ、喫煙可能居酒屋、店舗詳細への内部リンクを#{link_count}件追加する。",
            "expected_ctr_delta" => "内部回遊 +0.3 pages/session",
            "expected_rank_delta" => "+0.5〜1.0位"
          }
        )
      end

      def content_gap_issue
        return if recent_article_activity_count.positive?
        return if recent_impressions.zero? && latest_serp_analysis.blank?

        keywords = content_keywords.first(3)

        issue(
          key: "seo_content_gap_articles",
          title: "検索需要があるテーマの記事を#{keywords.size}本追加する",
          description: "#{keywords.join(' / ')} の検索需要に対して、直近30日の記事作成/更新Activityがありません。",
          action_type: "seo_article",
          quantity: keywords.size,
          unit: "本",
          why: "GSC/SERPの検索需要はありますが、Article Activityが直近30日で0件です。",
          expected_effect: "新規検索入口 #{keywords.size}本、初月クリック +#{keywords.size * 20}",
          expected_value_yen: estimated_value(27_000),
          success_probability: 0.34,
          strategic_value_score: 64,
          risk_reduction_score: 24,
          expected_hours: keywords.size * 1.5,
          metadata: {
            "evidence_sources" => [ "gsc", "serp", "business_db" ],
            "source_query" => keywords.first,
            "target_genre" => "SEO記事",
            "current_value" => recent_article_activity_count,
            "benchmark_value" => keywords.size,
            "candidate_keywords" => keywords,
            "recommended_slug" => query_slug(keywords.first),
            "recommended_title" => "#{keywords.first}の探し方｜#{business.name}",
            "proposed_h1" => "#{keywords.first}の探し方",
            "proposed_title" => "【#{Date.current.year}年版】#{keywords.first}の探し方｜#{business.name}",
            "proposed_meta_description" => "#{keywords.first}を探す人向けに、喫煙可否・エリア・お店の選び方を整理。#{business.name}で条件に合うお店を確認できます。",
            "candidate_pages" => keywords.map { |keyword| "/articles/#{query_slug(keyword)}" },
            "expected_ctr_delta" => "+#{keywords.size * 20} clicks/月",
            "expected_rank_delta" => "新規流入"
          }
        )
      end

      def shop_data_issue
        return unless shop_like_business?
        return if recent_shop_created_count >= 20

        area = priority_area
        add_count = [ 80 - recent_shop_created_count, 30 ].max
        add_count = [ add_count, 150 ].min

        issue(
          key: "seo_shop_data_shortage",
          title: "#{area}エリアの掲載店舗を#{add_count}件追加する",
          description: "#{business.name}の店舗DB型SEOで、#{area}の掲載店舗数を増やす課題です。",
          action_type: "data_preparation",
          quantity: add_count,
          unit: "件",
          why: "直近30日のShop作成Activityが#{recent_shop_created_count}件で、エリア検索の受け皿が不足しています。",
          expected_effect: "#{area}関連検索の受け皿 +#{add_count}店舗、期待利益 +#{yen_label(estimated_value(20_000))}",
          expected_value_yen: estimated_value(20_000),
          success_probability: 0.43,
          strategic_value_score: 56,
          risk_reduction_score: 36,
          expected_hours: (add_count * 20 / 3600.0).round(2),
          metadata: {
            "evidence_sources" => [ "business_db", "activity_log" ],
            "source_metric" => "shop_activity",
            "target_area" => area,
            "current_value" => recent_shop_created_count,
            "benchmark_value" => 80,
            "candidate_pages" => [ "#{area}エリア一覧", "#{area}喫煙可能店舗一覧", "店舗詳細ページ" ],
            "target_files" => [
              "app/models/shop.rb",
              "app/controllers/shops_controller.rb",
              "app/views/shops/index.html.erb"
            ],
            "completion_criteria" => [
              "#{area}エリアのShopが#{add_count}件追加または登録待ちになっている",
              "喫煙ステータス・住所・地図導線が保存されている",
              "重複確認メモが残っている",
              "ActionResult登録用の変更メモが生成される"
            ],
            "expected_ctr_delta" => "#{area}流入 +#{[ add_count / 5, 10 ].max} clicks/月",
            "expected_rank_delta" => "エリアロングテール強化"
          }
        )
      end

      def verified_shop_issue
        return unless shop_like_business?

        unverified_count = recent_shop_unverified_count
        return if unverified_count < 30

        target_count = [ unverified_count, 100 ].min

        issue(
          key: "seo_shop_verification_low",
          title: "未確認店舗を#{target_count}件確認済みにする",
          description: "#{business.name}の店舗信頼性を上げるため、喫煙情報の確認済み化を進めます。",
          action_type: "data_preparation",
          quantity: target_count,
          unit: "件",
          why: "BusinessActivityLog上、未確認または喫煙確認が必要な店舗Activityが#{unverified_count}件あります。",
          expected_effect: "店舗詳細CVR +0.4pt、地図クリック +#{[ target_count / 10, 5 ].max}/週",
          expected_value_yen: estimated_value(16_000),
          success_probability: 0.46,
          strategic_value_score: 48,
          risk_reduction_score: 50,
          expected_hours: (target_count * 30 / 3600.0).round(2),
          metadata: {
            "evidence_sources" => [ "business_db", "activity_log" ],
            "source_metric" => "smoking_verified_rate",
            "current_value" => unverified_count,
            "benchmark_value" => 0,
            "candidate_pages" => [ "店舗編集画面", "店舗詳細ページ", "エリア一覧ページ" ],
            "completion_criteria" => [
              "対象店舗#{target_count}件の喫煙情報が確認済みになっている",
              "紙タバコ/加熱式の区別が分かる範囲で保存されている",
              "確認済み化ActivityがBusinessActivityLogに残っている",
              "ActionResult登録用の変更メモが生成される"
            ]
          }
        )
      end

      def issue(**attributes)
        Issue.new(**{ confidence_score: confidence_score }.merge(attributes))
      end

      def recent7_metrics
        @recent7_metrics ||= business.business_metric_dailies.where(recorded_on: (today - 6)..today).to_a
      end

      def confidence_score
        case recent30_metrics.size
        when 0 then 18
        when 1..2 then 24
        when 3..6 then 34
        when 7...14 then 42
        when 14...30 then 52
        else 64
        end
      end

      def recent30_metrics
        @recent30_metrics ||= business.business_metric_dailies.where(recorded_on: (today - 29)..today).to_a
      end

      def recent_total(metric)
        recent7_metrics.sum { |record| record.public_send(metric).to_i }
      end

      def recent_average(metric)
        values = recent7_metrics.filter_map { |record| record.public_send(metric).to_d if record.public_send(metric).to_d.positive? }
        return 0.to_d if values.empty?

        values.sum / values.size
      end

      def recent_impressions
        @recent_impressions ||= recent_total(:impressions)
      end

      def recent_clicks
        @recent_clicks ||= recent_total(:clicks)
      end

      def recent_pageviews
        @recent_pageviews ||= recent_total(:pageviews)
      end

      def recent_sessions
        @recent_sessions ||= recent_total(:sessions)
      end

      def recent_conversions
        @recent_conversions ||= recent_total(:conversions)
      end

      def recent_conversion_clicks
        recent_total(:phone_clicks) + recent_total(:map_clicks) + recent_total(:affiliate_clicks)
      end

      def recent_ctr
        return 0.to_d if recent_impressions.zero?

        recent_clicks.to_d / recent_impressions.to_d
      end

      def recent_views_per_session
        return 0.to_d if recent_sessions.zero?

        recent_pageviews.to_d / recent_sessions.to_d
      end

      def latest_serp_analysis
        @latest_serp_analysis ||= business.serp_analyses.successful.order(analyzed_at: :desc, created_at: :desc).first
      end

      def relevant_serp_count(analysis)
        relevance_filter(analysis).relevant_results(serp_rows(analysis)).size
      end

      def branded_gap?(analysis)
        relevance_filter(analysis).branded_query? && relevant_serp_count(analysis) < 3
      end

      def relevance_filter(analysis)
        Aicoo::Serp::ResultRelevance.new(business:, query: analysis.keyword)
      end

      def serp_rows(analysis)
        analysis.serp_results.order(:position).limit(5).map do |row|
          { "position" => row.position, "title" => row.title, "url" => row.url, "snippet" => row.snippet }
        end
      end

      def serp_common_words(analysis)
        titles = serp_rows(analysis).map { |row| row["title"].to_s }
        found = %w[比較 口コミ 掲載件数 おすすめ 喫煙 居酒屋 カフェ エリア 地図].select do |word|
          titles.any? { |title| title.include?(word) }
        end
        found.presence || %w[比較 口コミ 掲載件数]
      end

      def recent_article_activity_count
        @recent_article_activity_count ||= business.business_activity_logs
                                                   .where(resource_type: "Article", occurred_at: 30.days.ago..Time.current)
                                                   .count
      end

      def recent_shop_logs
        @recent_shop_logs ||= business.business_activity_logs
                                    .where(resource_type: "Shop", occurred_at: 30.days.ago..Time.current)
                                    .to_a
      end

      def recent_shop_created_count
        recent_shop_logs.count { |log| log.activity_type.to_s.include?("created") || log.activity_type.to_s.include?("shop") }
      end

      def recent_shop_unverified_count
        recent_shop_logs.count do |log|
          metadata = log.metadata.to_h
          status = metadata["smoking_status"].to_s
          verified = metadata["verified"] || metadata["smoking_verified"]
          verified == false || status.blank? || status.match?(/未確認|unknown|unverified/i)
        end
      end

      def content_keywords
        explicit = business.serp_queries.enabled.order(priority: :asc).limit(3).pluck(:query)
        explicit = [ latest_serp_analysis&.keyword ].compact_blank if explicit.blank?
        explicit.presence || DEFAULT_AREA_KEYWORDS
      end

      def primary_query
        content_keywords.first
      end

      def priority_area
        text = [ primary_query, business.description, business.category ].join(" ")
        return "難波" if text.include?("難波")
        return "梅田" if text.include?("梅田")
        return "福島" if text.include?("福島")

        "大阪"
      end

      def candidate_pages_for_seo
        [ "流入上位記事", "エリア一覧ページ", "カテゴリ一覧ページ" ]
      end

      def candidate_pages_for_query(query)
        [
          "/articles/#{query_slug(query)}",
          "#{priority_area}エリア一覧",
          "関連カテゴリ一覧"
        ]
      end

      def query_slug(query)
        query.to_s.parameterize.presence || "seo-opportunity-#{today.strftime('%Y%m%d')}"
      end

      def shop_like_business?
        text = "#{business.name} #{business.category} #{business.description}".downcase
        text.match?(/店舗|店|shop|restaurant|cafe|喫煙|吸えログ/)
      end

      def estimated_value(base_value)
        revenue = business.revenue_events.revenue.where(occurred_on: (today - 29)..today).sum(:amount).to_i
        [ base_value + revenue, base_value * 3 ].min
      end

      def estimated_click_lift(target_count)
        [ (recent_impressions * 0.008).round, target_count * 5 ].max
      end

      def percent(value)
        "#{(value.to_d * 100).round(1)}%"
      end

      def yen_label(value)
        "¥#{value.to_i.to_fs(:delimited)}"
      end
    end
  end
end
