require "csv"
require "digest"
require "json"
require "uri"

module Aicoo
  module CandidateGenerators
    class SuelogGenerator
      Result = Data.define(:created, :skipped, :health) do
        def created_count = created.size
        def skipped_count = skipped.size

        def diagnostics
          {
            created_count:,
            skipped_count:,
            skipped_reasons: skipped.first(20),
            health: health&.diagnostics
          }
        end
      end

      CLICK_LOOKBACK = 30.days
      STALE_VERIFICATION_DAYS = 180
      SMOKING_LIMIT = 20
      PHONE_LIMIT = 10
      CLEANUP_LIMIT = 10
      ARTICLE_LIMIT = 20
      MIN_GSC_IMPRESSIONS = 20
      OWNER_HOSTS = %w[suelog.jp www.suelog.jp].freeze

      def self.target?(business)
        Aicoo::Suelog::SiteInsightsAdapter.target?(business)
      end

      def self.call(...)
        new(...).call
      end

      def initialize(business:, today: Date.current)
        @business = business
        @today = today.to_date
      end

      def call
        return Result.new(created: [], skipped: [ "not_suelog_business" ], health: nil) unless self.class.target?(business)

        health = Aicoo::ExternalSources::SuelogHealthCheck.call
        return Result.new(created: [], skipped: [ health.code ], health:) unless health.success?

        created = []
        skipped = []
        created.concat(create_smoking_info_candidates(skipped:))
        created.concat(create_phone_verify_candidates(skipped:))
        created.concat(create_shop_data_cleanup_candidates(skipped:))
        created.concat(create_article_candidates(skipped:))

        Result.new(created:, skipped:, health:)
      rescue StandardError => e
        Rails.logger.warn("[SuelogGenerator] skipped: #{e.class}: #{safe_error_message(e)}")
        Result.new(created: [], skipped: [ "suelog_generator_failed" ], health: nil)
      end

      private

      attr_reader :business, :today

      def create_smoking_info_candidates(skipped:)
        shops = verification_candidate_shops
        click_counts = click_counts_for(shops.map(&:id))
        shops.sort_by { |shop| [ -click_counts.fetch(shop.id, 0), shop.last_confirmed_on || Date.new(1900, 1, 1) ] }
             .first(SMOKING_LIMIT)
             .filter_map do |shop|
          create_candidate(
            action_type: "smoking_info_verify",
            title: "#{shop.name}の喫煙情報を確認する",
            description: "#{shop.area.presence || 'エリア未設定'} / #{shop.smoking_area_label} / #{shop.smoking_type_label}",
            external_record_id: shop.id,
            target_query: nil,
            immediate_value_yen: estimated_shop_action_value(action_type: "smoking_info_verify", click_count: click_counts.fetch(shop.id, 0)),
            expected_hours: 0.08,
            success_probability: 0.82,
            strategic_value_score: 45,
            metadata: shop_metadata(shop, click_counts).merge(
              "value_model" => suelog_value_model,
              "recommended_verification_method" => verification_method_for(shop),
              "priority_reason" => priority_reason_for(shop, click_counts.fetch(shop.id, 0)),
              "action_plan" => {
                "owner_output" => "#{shop.name}へ喫煙可否を確認する",
                "execution_steps" => [
                  "店舗情報を開く",
                  "電話または公式情報で喫煙可否を確認する",
                  "smoking_area / smoking_type / last_confirmed_on を更新する"
                ]
              }
            ),
            evaluation_reason: "suelog_db: 未確認/不明/古い喫煙情報を検出。直近クリック=#{click_counts.fetch(shop.id, 0)}"
          )
        rescue ActiveRecord::RecordInvalid => e
          skipped << "smoking_info_verify_invalid:#{shop.id}:#{e.record.errors.full_messages.join(',')}"
          nil
        end.compact
      end

      def create_phone_verify_candidates(skipped:)
        shops = verification_candidate_shops.select { |shop| shop.phone.to_s.present? && !shop.phone_check_on_hold? }
        click_counts = click_counts_for(shops.map(&:id))
        shops.sort_by { |shop| -click_counts.fetch(shop.id, 0) }
             .first(PHONE_LIMIT)
             .filter_map do |shop|
          next if click_counts.fetch(shop.id, 0).zero? && shop.last_confirmed_on.present?

          create_candidate(
            action_type: "shop_phone_verify",
            title: "#{shop.name}へ電話確認する",
            description: "電話番号あり / #{shop.area.presence || 'エリア未設定'} / 直近クリック #{click_counts.fetch(shop.id, 0)}",
            external_record_id: shop.id,
            target_query: nil,
            immediate_value_yen: estimated_shop_action_value(action_type: "shop_phone_verify", click_count: click_counts.fetch(shop.id, 0)),
            expected_hours: 0.1,
            success_probability: 0.78,
            strategic_value_score: 50,
            metadata: shop_metadata(shop, click_counts).merge(
              "value_model" => suelog_value_model,
              "recommended_verification_method" => "phone",
              "priority_reason" => "電話番号があり、喫煙情報が不明または古いため電話確認で解決できます。",
              "action_plan" => {
                "owner_output" => "#{shop.name}へ電話して喫煙情報を確認する",
                "execution_steps" => [
                  "電話番号へ架電する",
                  "紙タバコ/加熱式/席喫煙/喫煙所を確認する",
                  "確認結果とlast_confirmed_onを更新する"
                ]
              }
            ),
            evaluation_reason: "suelog_db: 電話確認可能な未確認店舗。直近クリック=#{click_counts.fetch(shop.id, 0)}"
          )
        rescue ActiveRecord::RecordInvalid => e
          skipped << "shop_phone_verify_invalid:#{shop.id}:#{e.record.errors.full_messages.join(',')}"
          nil
        end.compact
      end

      def create_shop_data_cleanup_candidates(skipped:)
        shops = ::Suelog::Shop.approved
          .where("on_hold = TRUE OR hold_reason IS NOT NULL")
          .select(:id, :name, :area, :genre, :phone, :smoking_area, :smoking_type, :smoking_unverified, :last_confirmed_on, :on_hold, :hold_reason, :phone_check_on_hold, :updated_at)
          .order(updated_at: :asc)
          .limit(100)
          .to_a
        click_counts = click_counts_for(shops.map(&:id))
        shops.sort_by { |shop| [ -click_counts.fetch(shop.id, 0), shop.updated_at || Time.zone.at(0) ] }
             .first(CLEANUP_LIMIT)
             .filter_map do |shop|
          create_candidate(
            action_type: "shop_data_cleanup",
            title: "#{shop.name}の保留/古い店舗データを整理する",
            description: "#{shop.area.presence || 'エリア未設定'} / #{shop.hold_reason.presence || '保留理由未設定'} / 直近クリック #{click_counts.fetch(shop.id, 0)}",
            external_record_id: shop.id,
            target_query: nil,
            immediate_value_yen: estimated_shop_action_value(action_type: "shop_data_cleanup", click_count: click_counts.fetch(shop.id, 0)),
            expected_hours: 0.12,
            success_probability: 0.65,
            strategic_value_score: 42,
            metadata: shop_metadata(shop, click_counts).merge(
              "value_model" => suelog_value_model,
              "cleanup_reason" => shop.hold_reason.presence || "on_hold",
              "action_plan" => {
                "owner_output" => "#{shop.name}の保留理由と店舗データを整理する",
                "execution_steps" => [
                  "保留理由を確認する",
                  "住所/閉店/重複/喫煙情報のどれが問題か切り分ける",
                  "必要な項目を更新し、保留を解除または維持理由を更新する"
                ]
              }
            ),
            evaluation_reason: "suelog_db: 保留/古い店舗データを検出。直近クリック=#{click_counts.fetch(shop.id, 0)}"
          )
        rescue ActiveRecord::RecordInvalid => e
          skipped << "shop_data_cleanup_invalid:#{shop.id}:#{e.record.errors.full_messages.join(',')}"
          nil
        end.compact
      end

      def create_article_candidates(skipped:)
        articles = ::Suelog::Article.published.limit(500).to_a
        gsc_rows.first(ARTICLE_LIMIT).filter_map do |row|
          query = row.fetch(:query).to_s.squish
          next if query.blank? || row.fetch(:impressions).to_i < MIN_GSC_IMPRESSIONS

          matched_article = article_for(row:, articles:)
          if matched_article
            create_article_update_candidate(row:, article: matched_article)
          else
            create_article_create_candidate(row:)
          end
        rescue ActiveRecord::RecordInvalid => e
          skipped << "article_candidate_invalid:#{row[:query]}:#{e.record.errors.full_messages.join(',')}"
          nil
        end.compact
      end

      def create_article_update_candidate(row:, article:)
        create_candidate(
          action_type: "article_update",
          title: "「#{row[:query]}」流入の既存記事を改訂する",
          description: "#{article.title} / CTR #{percent(row[:ctr])} / 平均順位 #{row[:position]}",
          external_record_id: article.id,
          target_query: row[:query],
          immediate_value_yen: article_expected_value(row),
          expected_hours: 0.75,
          success_probability: 0.58,
          strategic_value_score: 55,
          metadata: article_metadata(row).merge(
            "value_model" => suelog_value_model,
            "article_id" => article.id,
            "article_title" => article.title,
            "article_slug" => article.slug,
            "target_url" => article.public_path,
            "target_url_type" => "own_existing",
            "url_classification" => "own_existing",
            "page_exists" => true,
            "matched_article_id" => article.id,
            "current_title" => article.title,
            "current_seo_title" => article.seo_title,
            "current_meta_description" => article.meta_description,
            "revision_reason" => "GSC landing pageまたはqueryが公開済みArticleに対応しています。",
            "title_suggestion" => "#{row[:query]}｜喫煙できる飲食店を探すなら吸えログ",
            "meta_suggestion" => "#{row[:query]}で探している人向けに、喫煙可否・エリア・ジャンルから店舗を探せる情報を整理します。",
            "h1_suggestion" => "#{row[:query]}で探す喫煙可能店",
            "additional_sections" => [ "探し方", "おすすめ条件", "よくある質問" ],
            "action_plan" => {
              "owner_output" => "既存記事「#{article.title}」を「#{row[:query]}」向けに改訂する",
              "execution_steps" => [ "title/metaを見直す", "検索意図に合う見出しを追加する", "店舗候補と内部リンクを追加する" ]
            }
          ),
          evaluation_reason: "suelog_db+gsc: queryに対応する公開済みArticle##{article.id}が存在するためarticle_update"
        )
      end

      def create_article_create_candidate(row:)
        slug = recommended_slug_for(row[:query])
        create_candidate(
          action_type: "article_create",
          title: "「#{row[:query]}」向けの記事を作成する",
          description: "対応する公開済みArticleが見つかりません。impressions=#{row[:impressions]} clicks=#{row[:clicks]}",
          external_record_id: query_external_id(row[:query]),
          target_query: row[:query],
          immediate_value_yen: article_expected_value(row),
          expected_hours: 1.5,
          success_probability: 0.48,
          strategic_value_score: 60,
          metadata: article_metadata(row).merge(
            "value_model" => suelog_value_model,
            "recommended_title" => "#{row[:query]}｜喫煙できる飲食店を探すなら吸えログ",
            "recommended_slug" => slug,
            "recommended_url" => "/articles/#{slug}",
            "planned_url" => "/articles/#{slug}",
            "planned_url_type" => "proposed_new",
            "target_url_type" => "proposed_new",
            "url_classification" => "proposed_new",
            "article_summary" => "検索クエリ「#{row[:query]}」の意図に対応するまとめ記事を作成します。",
            "article_reason" => "GSCに検索需要がありますが、吸えログDB上に対応する公開済みArticleが存在しません。",
            "article_outline" => [ "H1 #{row[:query]}", "H2 探している人の条件", "H2 喫煙可否で選ぶ", "H2 エリア/ジャンル別の探し方", "H2 FAQ" ],
            "required_data" => [ "掲載候補店舗", "内部リンク元候補", "必要画像", "確認事項" ],
            "candidate_shops" => candidate_shops_for(row[:query]),
            "internal_link_candidates" => internal_link_candidates_for(row[:query]),
            "page_exists" => false,
            "matched_article_id" => nil,
            "action_plan" => {
              "owner_output" => "「#{row[:query]}」向けの記事企画を作成する",
              "execution_steps" => [ "記事テーマを確認する", "掲載候補店舗を選ぶ", "記事作成へ進めるか判断する" ]
            }
          ),
          evaluation_reason: "suelog_db+gsc: 対応Articleが存在しないためarticle_create。存在しないページへのtitle/meta改善は生成しません。"
        )
      end

      def create_candidate(action_type:, title:, description:, external_record_id:, target_query:, immediate_value_yen:, expected_hours:, success_probability:, strategic_value_score:, metadata:, evaluation_reason:)
        return if duplicate_candidate?(action_type:, external_record_id:, target_query:)

        value_model = valuation_model_for(
          action_type:,
          raw_value_yen: immediate_value_yen,
          expected_hours:,
          success_probability:,
          metadata:
        )
        Aicoo::ActionCandidateUpserter.call(
          business:,
          attributes: {
            title:,
            description:,
            action_type:,
            status: value_model.fetch("valuation_review_required") ? "valuation_review_required" : "idea",
            generation_source: "suelog_db",
            immediate_value_yen: immediate_value_yen.to_i,
            success_probability:,
            strategic_value_score:,
            risk_reduction_score: 20,
            expected_hours:,
            cost_yen: estimated_labor_cost_yen(expected_hours),
            priority_score: candidate_priority_score(
              value_yen: immediate_value_yen,
              expected_hours:,
              success_probability:,
              strategic_value_score:,
              value_model:
            ),
            evaluation_reason:,
            execution_prompt: nil,
            metadata: metadata.merge(
              "value_model" => value_model,
              "external_source" => "suelog_db",
              "external_record_id" => external_record_id.to_s,
              "target_query" => target_query.to_s,
              "execution_mode" => execution_mode_for(action_type),
              "data_sources_used" => (Array(metadata["data_sources_used"]) + %w[suelog_db]).uniq,
              "created_by" => self.class.name,
              "raw_immediate_value_yen" => immediate_value_yen.to_i
            )
          }
        )
      end

      def execution_mode_for(action_type)
        case action_type
        when "smoking_info_verify", "shop_phone_verify" then "manual_operation"
        when "shop_data_cleanup" then "data_operation"
        when "article_create", "article_update" then "content_creation"
        else "manual_operation"
        end
      end

      def duplicate_candidate?(action_type:, external_record_id:, target_query:)
        ActionCandidate.active_for_ranking
          .where(business:, action_type:)
          .where("metadata ->> 'external_source' = ?", "suelog_db")
          .where("metadata ->> 'external_record_id' = ?", external_record_id.to_s)
          .where("COALESCE(metadata ->> 'target_query', '') = ?", target_query.to_s)
          .exists?
      end

      def verification_candidate_shops
        ::Suelog::Shop.approved
          .verification_needed
          .select(:id, :name, :area, :genre, :phone, :smoking_area, :smoking_type, :smoking_unverified, :last_confirmed_on, :on_hold, :hold_reason, :phone_check_on_hold, :updated_at)
          .order(Arel.sql("last_confirmed_on ASC NULLS FIRST, updated_at DESC"))
          .limit(200)
          .to_a
      end

      def click_counts_for(shop_ids)
        return {} if shop_ids.blank?

        ::Suelog::ShopClick
          .where(shop_id: shop_ids, created_at: CLICK_LOOKBACK.ago..Time.current)
          .group(:shop_id)
          .count
      end

      def shop_metadata(shop, click_counts)
        {
          "shop_id" => shop.id,
          "shop_name" => shop.name,
          "area" => shop.area,
          "genre" => shop.genre,
          "phone_present" => shop.phone.present?,
          "smoking_area" => shop.smoking_area,
          "smoking_area_label" => shop.smoking_area_label,
          "smoking_type" => shop.smoking_type,
          "smoking_type_label" => shop.smoking_type_label,
          "smoking_unverified" => shop.smoking_unverified,
          "last_confirmed_on" => shop.last_confirmed_on,
          "recent_clicks" => click_counts.fetch(shop.id, 0),
          "on_hold" => shop.on_hold,
          "hold_reason" => shop.hold_reason,
          "source_table" => "shops",
          "data_sources_used" => %w[suelog_db]
        }
      end

      def priority_reason_for(shop, click_count)
        reasons = []
        reasons << "直近クリックが#{click_count}件あります" if click_count.positive?
        reasons << "喫煙区分が不明です" if shop.smoking_area == ::Suelog::Shop::UNKNOWN_SMOKING_AREA || shop.smoking_type == ::Suelog::Shop::UNKNOWN_SMOKING_TYPE
        reasons << "喫煙情報が未確認です" if shop.smoking_unverified
        reasons << "最終確認が古い/未設定です" if shop.stale_verification?
        reasons << "保留理由があります: #{shop.hold_reason}" if shop.hold_reason.present?
        reasons.join(" / ")
      end

      def verification_method_for(shop)
        return "phone" if shop.phone.present?
        return "official_site" if shop.hold_reason.to_s == "tabelog_suspect"

        "manual_research"
      end

      def article_metadata(row)
        {
          "source_table" => "articles",
          "data_sources_used" => %w[gsc suelog_db],
          "query" => row[:query],
          "target_query" => row[:query],
          "impressions" => row[:impressions],
          "clicks" => row[:clicks],
          "ctr" => row[:ctr],
          "average_position" => row[:position],
          "landing_page" => owner_landing_page?(row[:landing_page]) ? row[:landing_page] : nil,
          "external_landing_page_reference" => owner_landing_page?(row[:landing_page]) ? nil : row[:landing_page],
          "target_url_type" => owner_landing_page?(row[:landing_page]) ? "own_existing" : "external_reference",
          "url_classification" => owner_landing_page?(row[:landing_page]) ? "own_existing" : "external_reference",
          "expected_pv" => expected_pv(row),
          "expected_ctr_lift" => expected_ctr_lift(row)
        }
      end

      def gsc_rows
        @gsc_rows ||= business.data_sources
          .where(source_type: "gsc")
          .includes(:data_imports)
          .flat_map { |source| source.data_imports.recent.limit(3).to_a }
          .flat_map { |data_import| rows_from_gsc_import(data_import) }
          .compact_blank
          .uniq { |row| row[:query].to_s.downcase }
          .sort_by { |row| -row.fetch(:impressions).to_i }
      end

      def rows_from_gsc_import(data_import)
        rows = rows_from_processed_text(data_import.processed_text)
        rows = rows_from_raw_text(data_import.raw_text) if rows.empty?
        rows
      end

      def rows_from_processed_text(text)
        return [] if text.blank?

        CSV.parse(text, headers: true).filter_map do |row|
          query = value_from_row(row, "query", "検索クエリ", "keyword")
          next if query.blank?

          {
            query: query.to_s.squish,
            impressions: number_from_row(row, "impressions", "表示回数"),
            clicks: number_from_row(row, "clicks", "クリック数"),
            ctr: decimal_from_row(row, "ctr", "CTR"),
            position: decimal_from_row(row, "position", "掲載順位", "平均掲載順位"),
            landing_page: value_from_row(row, "page", "ページ", "url")
          }
        end
      rescue CSV::MalformedCSVError
        []
      end

      def rows_from_raw_text(text)
        return [] if text.blank?

        parsed = JSON.parse(text)
        Array(parsed["rows"]).filter_map do |row|
          query = Array(row["keys"]).first.presence || row["query"].presence
          next if query.blank?

          {
            query: query.to_s.squish,
            impressions: row["impressions"].to_i,
            clicks: row["clicks"].to_i,
            ctr: row["ctr"].to_d,
            position: row["position"].to_d,
            landing_page: Array(row["keys"])[1]
          }
        end
      rescue JSON::ParserError
        []
      end

      def value_from_row(row, *keys)
        keys.each do |key|
          value = row[key]
          return value if value.present?
        end
        nil
      end

      def number_from_row(row, *keys)
        value_from_row(row, *keys).to_s.delete(",").to_i
      end

      def decimal_from_row(row, *keys)
        value_from_row(row, *keys).to_s.delete("%").to_d
      end

      def article_for(row:, articles:)
        return if articles.blank?

        landing_slug = owner_landing_page?(row[:landing_page]) ? row[:landing_page].to_s[/\/articles\/([^\/?#]+)/, 1] : nil
        return articles.find { |article| article.slug == landing_slug } if landing_slug.present?

        articles.max_by { |article| article_relevance_score(article, row[:query]) }.then do |article|
          return unless article

          article_relevance_score(article, row[:query]) >= 12 ? article : nil
        end
      end

      def article_relevance_score(article, query)
        words_for(query).sum { |word| article.searchable_text.include?(word.downcase) ? 5 : 0 }
      end

      def words_for(query)
        query.to_s
          .gsub(/吸えログ|喫煙|喫煙可|喫煙可能|店|店舗|飲食店/, " ")
          .split(/[[:space:]　]+/)
          .map(&:squish)
          .reject { |word| word.length < 2 }
      end

      def candidate_shops_for(query)
        terms = words_for(query)
        scope = ::Suelog::Shop.approved.select(:id, :name, :area, :genre)
        if terms.any?
          conditions = terms.map.with_index { |_, index| "name ILIKE :q#{index} OR area ILIKE :q#{index} OR genre ILIKE :q#{index}" }.join(" OR ")
          binds = terms.each_with_index.to_h { |term, index| [ :"q#{index}", "%#{term}%" ] }
          scope = scope.where(conditions, binds)
        end
        scope.limit(8).map { |shop| { "shop_id" => shop.id, "name" => shop.name, "area" => shop.area, "genre" => shop.genre } }
      end

      def internal_link_candidates_for(query)
        words = words_for(query)
        ::Suelog::Article.published.limit(200).select { |article| words.any? { |word| article.searchable_text.include?(word.downcase) } }
          .first(5)
          .map { |article| { "article_id" => article.id, "title" => article.title, "path" => article.public_path } }
      end

      def recommended_slug_for(query)
        normalized_query = query.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        parameterized = normalized_query.parameterize
        normalized = parameterized.to_s.gsub(/\A-+|-+\z/, "").squish
        return normalized if normalized.match?(/\A[a-z0-9][a-z0-9-]{4,}[a-z0-9]\z/)

        "article-#{Digest::SHA1.hexdigest(normalized_query).first(10)}"
      end

      def query_external_id(query)
        "query:#{Digest::SHA1.hexdigest(query.to_s.downcase.squish).first(16)}"
      end

      def article_expected_value(row)
        impressions = row[:impressions].to_i
        current_ctr = row[:ctr].to_d
        target_ctr = target_ctr_for(row)
        incremental_clicks = [ impressions * [ target_ctr - current_ctr, 0.005.to_d ].max, 500 ].min
        value = incremental_clicks * suelog_value_model.fetch("value_per_click_yen").to_d
        [ value.round, 1_200 ].max
      end

      def expected_pv(row)
        [ (row[:impressions].to_i * target_ctr_for(row)).round, 10 ].max
      end

      def expected_ctr_lift(row)
        current = row[:ctr].to_d
        target = target_ctr_for(row)
        (target - current).round(4).to_s
      end

      def target_ctr_for(row)
        position = row[:position].to_d
        current = row[:ctr].to_d
        baseline =
          if position.positive? && position <= 5
            0.035.to_d
          elsif position <= 10
            0.025.to_d
          elsif position <= 30
            0.015.to_d
          else
            0.01.to_d
          end
        [ baseline, current + 0.005.to_d ].max
      end

      def estimated_shop_action_value(action_type:, click_count:)
        model = suelog_value_model
        base_clicks = [ click_count.to_i, 1 ].max
        multiplier = {
          "smoking_info_verify" => 2.5,
          "shop_phone_verify" => 3.0,
          "shop_data_cleanup" => 1.4
        }.fetch(action_type, 1.0)
        value = base_clicks * model.fetch("value_per_shop_click_yen").to_d * multiplier
        [ value.round, 800 ].max
      end

      def estimated_labor_cost_yen(expected_hours)
        (expected_hours.to_d * 1_500).round
      end

      def candidate_priority_score(value_yen:, expected_hours:, success_probability:, strategic_value_score:, value_model:)
        hours = [ expected_hours.to_d, 0.05.to_d ].max
        confidence = value_model.fetch("confidence").to_d
        evidence_factor = { "high" => 1.0.to_d, "medium" => 0.7.to_d, "low" => 0.35.to_d }.fetch(value_model.fetch("evidence_level"), 0.35.to_d)
        outlier_penalty = [ value_model.fetch("outlier_ratio").to_d / 10, 1 ].max
        ranking_value = value_yen.to_d * confidence * evidence_factor * success_probability.to_d / hours / outlier_penalty
        hourly_score = [ ranking_value / 1_000, 55 ].min
        confidence_score = (confidence * 20)
        strategic_score = strategic_value_score.to_i * 0.25
        [ (hourly_score + confidence_score + strategic_score).round, 100 ].min
      end

      def valuation_model_for(action_type:, raw_value_yen:, expected_hours:, success_probability:, metadata:)
        base = suelog_value_model
        raw_value_yen = raw_value_yen.to_i
        raw_expected_value_yen = (raw_value_yen.to_d * success_probability.to_d).round
        action_type_median = historical_median_value(action_type:)
        business_median = historical_median_value
        outlier_ratio = [
          ratio_against(raw_expected_value_yen, action_type_median),
          ratio_against(raw_expected_value_yen, business_median)
        ].compact.max || 1.to_d
        evidence = valuation_evidence_for(metadata:, base:, action_type_median:, business_median:)
        assumptions = valuation_assumptions_for(raw_expected_value_yen:, evidence:, outlier_ratio:)
        evidence_level = valuation_evidence_level(evidence)
        confidence = valuation_confidence(evidence_level:, outlier_ratio:, assumptions:)
        review_required = valuation_review_required?(
          raw_expected_value_yen:,
          evidence_level:,
          outlier_ratio:,
          assumptions:
        )

        base.merge(
          "raw_expected_value_yen" => raw_expected_value_yen,
          "adjusted_expected_value_yen" => valuation_adjusted_value(raw_expected_value_yen:, confidence:, evidence_level:, outlier_ratio:),
          "raw_immediate_value_yen" => raw_value_yen,
          "confidence" => confidence.to_f.round(2),
          "evidence_level" => evidence_level,
          "valuation_review_required" => review_required,
          "valuation_state" => review_required ? "valuation_review_required" : "accepted",
          "outlier_ratio" => outlier_ratio.to_f.round(2),
          "assumptions" => assumptions,
          "evidence" => evidence,
          "calculation_version" => "suelog_v3",
          "max_contribution_factor" => max_contribution_factor(metadata:, base:),
          "high_value_reason" => high_value_reason(raw_expected_value_yen:, evidence_level:, outlier_ratio:),
          "expected_hours" => expected_hours.to_s,
          "success_probability" => success_probability.to_s
        )
      end

      def valuation_evidence_for(metadata:, base:, action_type_median:, business_median:)
        {
          "impressions" => metadata["impressions"].to_i,
          "ctr_lift" => metadata["expected_ctr_lift"].to_s,
          "incremental_clicks" => metadata["expected_pv"].to_i,
          "value_per_click_yen" => base["value_per_click_yen"],
          "value_per_shop_click_yen" => base["value_per_shop_click_yen"],
          "cv_rate_proxy" => cv_rate_proxy(base),
          "profit_unit_source" => "ProxyScoreWeight phone/map/affiliate weights",
          "recent_90d" => base.slice(
            "business_clicks_90d",
            "phone_clicks_90d",
            "map_clicks_90d",
            "affiliate_clicks_90d",
            "near_conversion_count_90d",
            "near_conversion_proxy_value_90d"
          ),
          "similar_action_count" => similar_action_count(metadata["external_source"]),
          "similar_action_result_count" => similar_action_result_count,
          "action_type_median_yen" => action_type_median.to_i,
          "business_median_yen" => business_median.to_i,
          "recent_shop_clicks" => metadata["recent_clicks"].to_i,
          "data_points" => valuation_data_points(base:, metadata:)
        }
      end

      def valuation_adjusted_value(raw_expected_value_yen:, confidence:, evidence_level:, outlier_ratio:)
        evidence_factor = { "high" => 1.0.to_d, "medium" => 0.7.to_d, "low" => 0.35.to_d }.fetch(evidence_level, 0.35.to_d)
        outlier_penalty = [ outlier_ratio.to_d / 10, 1 ].max
        (raw_expected_value_yen.to_d * confidence.to_d * evidence_factor / outlier_penalty).round
      end

      def valuation_assumptions_for(raw_expected_value_yen:, evidence:, outlier_ratio:)
        assumptions = []
        assumptions << "直近90日のBusinessMetricDailyが少ないためクリック価値はfallbackを含みます" if evidence.dig("recent_90d", "business_clicks_90d").to_i < 100
        assumptions << "近接CV実績が少ないためvalue_per_clickの信頼度は低めです" if evidence.dig("recent_90d", "near_conversion_count_90d").to_i < 5
        assumptions << "類似ActionResultがないため実績補正は未反映です" if evidence["similar_action_result_count"].to_i.zero?
        assumptions << "同種候補中央値に対して#{outlier_ratio.to_f.round(1)}倍です" if outlier_ratio.to_d > 10
        assumptions << "100万円超のため前提確認が必要です" if raw_expected_value_yen > 1_000_000
        assumptions
      end

      def valuation_evidence_level(evidence)
        return "high" if evidence.dig("recent_90d", "business_clicks_90d").to_i >= 1_000 &&
                         evidence.dig("recent_90d", "near_conversion_count_90d").to_i >= 20 &&
                         evidence["similar_action_result_count"].to_i.positive?
        return "medium" if evidence.dig("recent_90d", "business_clicks_90d").to_i >= 100 &&
                           evidence.dig("recent_90d", "near_conversion_count_90d").to_i >= 5

        "low"
      end

      def valuation_confidence(evidence_level:, outlier_ratio:, assumptions:)
        base = { "high" => 0.9.to_d, "medium" => 0.65.to_d, "low" => 0.35.to_d }.fetch(evidence_level, 0.35.to_d)
        outlier_penalty = outlier_ratio.to_d > 10 ? 0.2.to_d : 0.to_d
        assumption_penalty = [ assumptions.size * 0.05, 0.25 ].min.to_d
        [ base - outlier_penalty - assumption_penalty, 0.1.to_d ].max
      end

      def valuation_review_required?(raw_expected_value_yen:, evidence_level:, outlier_ratio:, assumptions:)
        return false if raw_expected_value_yen <= 1_000_000
        return false if evidence_level == "high" && outlier_ratio.to_d <= 10 && assumptions.size <= 1

        true
      end

      def valuation_data_points(base:, metadata:)
        [
          base["business_clicks_90d"].to_i,
          base["near_conversion_count_90d"].to_i,
          metadata["impressions"].to_i,
          metadata["recent_clicks"].to_i
        ].count(&:positive?)
      end

      def max_contribution_factor(metadata:, base:)
        if metadata["impressions"].to_i.positive?
          "GSC impressions"
        elsif metadata["recent_clicks"].to_i.positive?
          "Suelog ShopClick"
        elsif base["near_conversion_proxy_value_90d"].to_d.positive?
          "90d conversion proxy"
        else
          "fallback assumptions"
        end
      end

      def high_value_reason(raw_expected_value_yen:, evidence_level:, outlier_ratio:)
        return nil if raw_expected_value_yen <= 250_000

        "期待利益#{raw_expected_value_yen}円 / evidence=#{evidence_level} / outlier_ratio=#{outlier_ratio.to_f.round(2)}"
      end

      def historical_median_value(action_type: nil)
        scope = ActionCandidate.where(business:, generation_source: "suelog_db")
        scope = scope.where(action_type:) if action_type
        median(scope.where("expected_profit_yen > 0").limit(200).pluck(:expected_profit_yen))
      end

      def median(values)
        sorted = values.compact.map(&:to_d).sort
        return nil if sorted.empty?

        mid = sorted.length / 2
        sorted.length.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2)
      end

      def ratio_against(value, baseline)
        return nil if baseline.blank? || baseline.to_d <= 0

        value.to_d / baseline.to_d
      end

      def similar_action_count(_external_source)
        ActionCandidate.where(business:, generation_source: "suelog_db").where.not(status: ActionCandidate::INACTIVE_STATUSES).count
      end

      def similar_action_result_count
        ActionResult.joins(:action_candidate).where(action_candidates: { business_id: business.id, generation_source: "suelog_db" }).count
      end

      def cv_rate_proxy(base)
        clicks = base["business_clicks_90d"].to_i
        return "0" if clicks.zero?

        (base["near_conversion_count_90d"].to_d / clicks).round(4).to_s
      end

      def suelog_value_model
        @suelog_value_model ||= begin
          metrics = business.business_metric_dailies.where(recorded_on: 90.days.ago.to_date..today)
          clicks = metrics.sum(:clicks).to_i
          phone_clicks = metrics.sum(:phone_clicks).to_i
          map_clicks = metrics.sum(:map_clicks).to_i
          affiliate_clicks = metrics.sum(:affiliate_clicks).to_i
          near_conversion_count = phone_clicks + map_clicks + affiliate_clicks
          weights = ProxyScoreWeight.for_business(business)
          near_conversion_value =
            (phone_clicks * weights.weight_for(:phone_clicks).to_d) +
            (map_clicks * weights.weight_for(:map_clicks).to_d) +
            (affiliate_clicks * weights.weight_for(:affiliate_clicks).to_d)
          value_per_click = if clicks.positive? && near_conversion_value.positive?
            near_conversion_value / clicks
          else
            8.to_d
          end
          value_per_shop_click = if near_conversion_count.positive?
            near_conversion_value / near_conversion_count
          else
            12.to_d
          end

          {
            "source" => "business_metric_dailies_90d_and_suelog_shop_clicks",
            "lookback_days" => 90,
            "business_clicks_90d" => clicks,
            "phone_clicks_90d" => phone_clicks,
            "map_clicks_90d" => map_clicks,
            "affiliate_clicks_90d" => affiliate_clicks,
            "near_conversion_count_90d" => near_conversion_count,
            "near_conversion_proxy_value_90d" => near_conversion_value.round(2).to_s,
            "value_per_click_yen" => clamp_decimal(value_per_click, min: 2, max: 80).round(2).to_s,
            "value_per_shop_click_yen" => clamp_decimal(value_per_shop_click, min: 5, max: 120).round(2).to_s,
            "calibration_target" => "ActionResult / BusinessMetricDailyで継続補正",
            "high_confidence" => clicks >= 100 && near_conversion_count >= 5
          }
        end
      end

      def clamp_decimal(value, min:, max:)
        [[ value.to_d, min.to_d ].max, max.to_d].min
      end

      def owner_landing_page?(url)
        text = url.to_s
        return false if text.blank?
        return true if text.start_with?("/")

        uri = URI.parse(text)
        uri.host.in?(OWNER_HOSTS)
      rescue URI::InvalidURIError
        false
      end

      def percent(value)
        "#{(value.to_d * 100).round(1)}%"
      end

      def safe_error_message(error)
        error.message.to_s.gsub(ENV["SUELOG_DATABASE_URL"].to_s, "[FILTERED]")
      end
    end
  end
end
