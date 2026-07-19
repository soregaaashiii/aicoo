module Aicoo
  class ArticleOpportunityExecutionBriefBuilder
    Result = Data.define(:title, :description, :execution_prompt, :metadata)

    SUELOG_HOST = "https://suelog.jp".freeze
    CODEX_POSSIBLE_TYPES = %w[ctr_improvement rank_improvement internal_link_addition content_update].freeze
    HUMAN_REQUIRED_TYPES = %w[shop_addition verified_shop_addition].freeze
    COMPLETION_DAYS = 28

    def self.call(...)
      new(...).call
    end

    def initialize(business:, snapshot:, payload:, opportunity:, score:, breakdown:)
      @business = business
      @snapshot = snapshot
      @payload = payload.to_h.deep_stringify_keys
      @opportunity = opportunity.to_h.deep_stringify_keys
      @score = score
      @breakdown = breakdown.to_h.deep_stringify_keys
    end

    def call
      brief = execution_brief
      Result.new(
        title: title_for(brief),
        description: description_for(brief),
        execution_prompt: execution_prompt_for(brief),
        metadata: {
          "execution_brief" => brief,
          "execution_readiness" => execution_readiness_for(brief),
          "codex_eligible" => brief.dig("execution", "codex_eligible"),
          "auto_revision" => false,
          "auto_merge" => false,
          "auto_deploy" => false
        }
      )
    end

    private

    attr_reader :business, :snapshot, :payload, :opportunity, :score, :breakdown

    def execution_brief
      @execution_brief ||= begin
        changes = recommended_changes
        missing = missing_information_for(changes)
        execution = execution_for(changes, missing)
        {
          "target" => target,
          "current_state" => current_state,
          "evidence" => evidence,
          "recommended_changes" => changes,
          "completion_conditions" => completion_conditions,
          "expected_result" => expected_result,
          "execution" => execution,
          "missing_information" => missing,
          "safety" => safety_for(execution)
        }
      end
    end

    def target
      {
        "business_id" => business.id,
        "business_name" => business.name,
        "article_id" => payload["article_id"],
        "article_title" => article_title,
        "article_path" => article_path,
        "target_url" => target_url,
        "target_type" => target_type,
        "improvement_type" => opportunity_type,
        "snapshot_id" => snapshot.id
      }
    end

    def current_state
      gsc = gsc_metrics
      ga4 = ga4_metrics
      shop_click = shop_click_metrics
      article = article_metrics
      relative = relative_metrics
      {
        "impressions" => nullable_number(gsc["impressions"]),
        "clicks" => nullable_number(gsc["clicks"]),
        "ctr" => nullable_number(gsc["ctr"]),
        "average_position" => nullable_number(gsc["average_position"]),
        "query_count" => nullable_number(gsc["query_count"]),
        "pageviews" => nullable_number(ga4["pageviews"]),
        "active_users" => nullable_number(ga4["active_users"]),
        "shop_clicks" => nullable_number(shop_click["total_clicks"]),
        "word_count" => nullable_number(article["word_count"]),
        "internal_link_count" => nullable_number(article["internal_link_count"]),
        "shop_count" => nullable_number(article["shop_count"]),
        "verified_shop_count" => nullable_number(article["verified_shop_count"]),
        "business_impression_rank" => nullable_number(relative["impression_rank"]),
        "business_ctr_rank" => nullable_number(relative["ctr_rank"]),
        "business_search_demand_rank" => nullable_number(relative["search_demand_rank"] || relative["impression_rank"]),
        "data_confidence" => data_confidence,
        "snapshot_date" => snapshot.captured_at&.iso8601 || payload["snapshot_generated_at"]
      }
    end

    def evidence
      {
        "gsc" => gsc_metrics.slice("available", "impressions", "clicks", "ctr", "average_position", "query_count", "top_queries"),
        "ga4" => ga4_metrics.slice("available", "pageviews", "active_users", "sessions", "engagement_seconds", "event_count"),
        "shop_click" => shop_click_metrics.slice("available", "total_clicks", "article_shop_clicks", "phone_clicks", "map_clicks", "affiliate_clicks"),
        "article_content" => article_metrics.slice("title", "word_count", "internal_link_count", "content_source", "updated_at"),
        "shop_database" => article_metrics.slice("shop_count", "verified_shop_count", "area", "genre"),
        "analyzer" => analyzer_evidence
      }
    end

    def analyzer_evidence
      diagnostics = payload["score_diagnostics"].to_h
      {
        "search_demand_score" => opportunity["search_demand_score"],
        "improvement_potential_score" => opportunity["improvement_potential_score"],
        "expected_improvement_score" => opportunity["expected_improvement_score"],
        "success_probability" => opportunity["success_probability"],
        "estimated_work_hours" => opportunity["estimated_work_hours"],
        "business_value" => opportunity["business_value"],
        "seo_opportunity" => breakdown["seo_opportunity"],
        "ctr_opportunity" => breakdown["ctr_opportunity"],
        "ranking_reason" => opportunity["ranking_reason"] || payload["ranking_reason"],
        "seo_reason" => diagnostics["seo_reason"] || payload.dig("score_reasons", "seo_opportunity"),
        "ctr_reason" => diagnostics["ctr_reason"] || payload.dig("score_reasons", "ctr_opportunity")
      }
    end

    def recommended_changes
      case opportunity_type
      when "ctr_improvement" then ctr_changes
      when "rank_improvement" then rank_changes
      when "internal_link_addition" then internal_link_changes
      when "content_update" then content_update_changes
      when "shop_addition" then shop_addition_changes
      when "verified_shop_addition" then verified_shop_addition_changes
      else monitoring_changes
      end
    end

    def ctr_changes
      queries = top_queries
      [
        change(
          change_type: "title_meta_review",
          target_element: "title/meta_description",
          instruction: "主要検索クエリと記事内容が一致するようにtitleとmeta descriptionを見直す。",
          evidence: {
            "top_queries" => queries,
            "business_average_ctr" => relative_metrics["ctr_average"],
            "ctr_gap_to_business" => relative_metrics["ctr_gap_to_business"],
            "query_data_status" => queries.any? ? "available" : "query_data_unavailable",
            "title_research_required" => queries.empty?
          },
          before: {
            "title" => current_article_title,
            "meta_description" => current_meta_description,
            "ctr" => gsc_metrics["ctr"]
          },
          after_goal: "記事内容と実データに反しない範囲で、主要クエリの検索意図が伝わるtitle/metaにする。",
          automation_level: queries.any? ? "codex_possible" : "research_required",
          requires_research: queries.empty?,
          requires_human_review: true
        )
      ]
    end

    def rank_changes
      [
        change(
          change_type: "content_structure_review",
          target_element: "article_body",
          instruction: "導入文・見出し・店舗導線が対象クエリの検索意図と対応しているか確認し、不足が実データで確認できる箇所だけ更新する。",
          evidence: {
            "average_position" => gsc_metrics["average_position"],
            "top_queries" => top_queries,
            "word_count" => article_metrics["word_count"],
            "shop_count" => article_metrics["shop_count"],
            "verified_shop_count" => article_metrics["verified_shop_count"],
            "internal_link_count" => article_metrics["internal_link_count"]
          },
          before: {
            "word_count" => article_metrics["word_count"],
            "internal_link_count" => article_metrics["internal_link_count"],
            "shop_count" => article_metrics["shop_count"],
            "verified_shop_count" => article_metrics["verified_shop_count"]
          },
          after_goal: "検索意図、見出し、店舗情報、内部リンクの対応関係を明確にする。",
          automation_level: "codex_possible",
          requires_research: top_queries.empty?,
          requires_human_review: true
        )
      ]
    end

    def internal_link_changes
      candidates = internal_link_candidates
      [
        change(
          change_type: "internal_link_addition",
          target_element: "article_body",
          instruction: candidates.any? ? "実在する関連記事・店舗ページ候補から、文脈に合う内部リンクを追加する。" : "内部リンク先候補を特定する。",
          evidence: {
            "current_internal_link_count" => article_metrics["internal_link_count"],
            "candidate_links" => candidates
          },
          before: { "internal_link_count" => article_metrics["internal_link_count"] },
          after_goal: candidates.any? ? "存在確認済みの自社内部URLだけを追加する。" : "存在確認済みの内部リンク候補を抽出する。",
          automation_level: candidates.any? ? "codex_possible" : "research_required",
          requires_research: candidates.empty?,
          requires_human_review: true
        )
      ]
    end

    def content_update_changes
      [
        change(
          change_type: "content_update",
          target_element: "article_body",
          instruction: "本文量・最終更新・店舗数・確認済店舗数を確認し、実データで不足が分かる箇所だけ構成整理する。",
          evidence: {
            "word_count" => article_metrics["word_count"],
            "updated_at" => article_metrics["updated_at"],
            "shop_count" => article_metrics["shop_count"],
            "verified_shop_count" => article_metrics["verified_shop_count"]
          },
          before: {
            "word_count" => article_metrics["word_count"],
            "updated_at" => article_metrics["updated_at"]
          },
          after_goal: "既存情報を捏造せず、見出し・導線・既存DB情報の表示を整理する。",
          automation_level: "codex_possible",
          requires_research: false,
          requires_human_review: true
        )
      ]
    end

    def shop_addition_changes
      candidates = shop_candidates
      [
        change(
          change_type: "shop_candidate_extraction",
          target_element: "article_shop_list",
          instruction: candidates.any? ? "DB内の実在候補店舗を確認し、記事テーマに合う掲載可否を人手で判断する。" : "記事テーマに合う未掲載店舗候補をDBまたは人手調査で特定する。",
          evidence: {
            "current_shop_count" => article_metrics["shop_count"],
            "target_shop_count" => target_shop_count,
            "shortage_count" => shop_shortage_count,
            "candidate_shops" => candidates,
            "candidate_filter" => shop_candidate_filter
          },
          before: { "shop_count" => article_metrics["shop_count"] },
          after_goal: "実在し、掲載してよい店舗だけを追加候補にする。",
          automation_level: candidates.any? ? "human_required" : "research_required",
          requires_research: candidates.empty?,
          requires_human_review: true
        )
      ]
    end

    def verified_shop_addition_changes
      candidates = unverified_shop_candidates
      [
        change(
          change_type: "shop_verification",
          target_element: "article_shop_facts",
          instruction: candidates.any? ? "未確認店舗の喫煙条件を人手で確認する。" : "確認対象店舗を特定する。",
          evidence: {
            "shop_count" => article_metrics["shop_count"],
            "verified_shop_count" => article_metrics["verified_shop_count"],
            "unverified_shop_count" => unverified_shop_count,
            "unverified_shops" => candidates,
            "verification_fields" => verification_fields
          },
          before: {
            "shop_count" => article_metrics["shop_count"],
            "verified_shop_count" => article_metrics["verified_shop_count"]
          },
          after_goal: "喫煙可否・紙タバコ可否・席喫煙可否などを確認済みにする。",
          automation_level: candidates.any? ? "human_required" : "research_required",
          requires_research: candidates.empty?,
          requires_human_review: true
        )
      ]
    end

    def monitoring_changes
      [
        change(
          change_type: "monitoring",
          target_element: "article_metrics",
          instruction: "次回SnapshotでGSC・GA4・ShopClickの推移を確認する。",
          evidence: analyzer_evidence,
          before: current_state,
          after_goal: "十分な改善根拠が出るまで観測する。",
          automation_level: "unavailable",
          requires_research: false,
          requires_human_review: false
        )
      ]
    end

    def change(change_type:, target_element:, instruction:, evidence:, before:, after_goal:, automation_level:, requires_research:, requires_human_review:)
      {
        "change_type" => change_type,
        "target_element" => target_element,
        "instruction" => instruction,
        "evidence" => evidence,
        "before" => before,
        "after_goal" => after_goal,
        "automation_level" => automation_level,
        "requires_research" => requires_research,
        "requires_human_review" => requires_human_review
      }
    end

    def completion_conditions
      base = [
        "対象記事とURLが一致している",
        "変更前後をActionResultまたは作業メモに保存した",
        "#{COMPLETION_DAYS}日後にGSC/GA4/ShopClickで評価する"
      ]
      case opportunity_type
      when "ctr_improvement"
        base + [
          "titleが対象クエリの検索意図と一致している",
          "meta descriptionが記事内容と一致している",
          "実データにない喫煙条件や店舗情報を追加していない"
        ]
      when "internal_link_addition"
        base + [ "追加リンクがすべて吸えログ内の実在URLである", "存在確認できないURLを追加していない" ]
      when "shop_addition"
        base + [ "追加候補店舗がDB上に実在する", "人手確認なしに新規店舗情報を公開していない" ]
      when "verified_shop_addition"
        base + [ "確認対象項目を記録した", "電話確認または公式情報確認が必要な項目を推測で埋めていない" ]
      else
        base + [ "本文・見出し・内部リンクが記事内容と矛盾していない" ]
      end
    end

    def expected_result
      {
        "expected_improvement_score" => nullable_number(opportunity["expected_improvement_score"]),
        "expected_click_gain" => expected_click_gain,
        "expected_ctr_range" => expected_ctr_range,
        "expected_position_range" => expected_position_range,
        "expected_pageview_gain" => nil,
        "expected_shop_click_gain" => nil,
        "evaluation_period_days" => COMPLETION_DAYS,
        "confidence" => data_confidence
      }
    end

    def execution_for(changes, missing)
      research_required = changes.any? { |row| row["requires_research"] } || missing.any?
      human_required = HUMAN_REQUIRED_TYPES.include?(opportunity_type) || changes.any? { |row| row["automation_level"] == "human_required" }
      review_required = changes.any? { |row| row["requires_human_review"] }
      codex_possible = CODEX_POSSIBLE_TYPES.include?(opportunity_type) && !research_required
      codex_eligible = codex_possible && !HUMAN_REQUIRED_TYPES.include?(opportunity_type)
      {
        "executor_type" => executor_type(codex_eligible:, human_required:, research_required:),
        "codex_eligible" => codex_eligible,
        "human_required" => human_required,
        "research_required" => research_required,
        "approval_required" => human_required || review_required || codex_eligible,
        "estimated_work_hours" => nullable_number(opportunity["estimated_work_hours"]),
        "risk_level" => human_required || research_required ? "medium" : "low",
        "rollback_possible" => !HUMAN_REQUIRED_TYPES.include?(opportunity_type),
        "suggested_next_action" => suggested_next_action(changes, missing)
      }
    end

    def safety_for(execution)
      {
        "factual_risk" => execution["human_required"] || execution["research_required"] ? "medium" : "low",
        "external_research_required" => execution["research_required"],
        "private_data_risk" => "low",
        "legal_risk" => HUMAN_REQUIRED_TYPES.include?(opportunity_type) ? "medium" : "low",
        "seo_risk" => opportunity_type.in?(%w[ctr_improvement rank_improvement]) ? "medium" : "low",
        "rollback_required" => execution["rollback_possible"],
        "prohibited_actions" => prohibited_actions
      }
    end

    def prohibited_actions
      [
        "未確認店舗情報の公開",
        "外部URLを自サイトURLとして扱う",
        "存在しない内部リンク追加",
        "店舗レビューの捏造",
        "喫煙条件の推測",
        "記事件数と掲載店舗数の不一致放置"
      ]
    end

    def missing_information_for(changes)
      missing = []
      missing << "対象記事URL未特定" if target_type != "existing_article"
      missing << "主要検索Query未取得" if opportunity_type.in?(%w[ctr_improvement rank_improvement]) && top_queries.empty?
      missing << "内部リンク先候補未特定" if opportunity_type == "internal_link_addition" && internal_link_candidates.empty?
      missing << "DB内店舗候補未特定" if opportunity_type == "shop_addition" && shop_candidates.empty?
      missing << "未確認店舗候補未特定" if opportunity_type == "verified_shop_addition" && unverified_shop_candidates.empty?
      missing << "recommended_changes未生成" if changes.empty?
      missing
    end

    def title_for(brief)
      case opportunity_type
      when "ctr_improvement"
        "#{article_title}のtitle/metaを主要クエリに合わせて見直す"
      when "rank_improvement"
        "#{article_title}の順位#{format_value(gsc_metrics['average_position'])}位を改善するため本文構成を更新する"
      when "internal_link_addition"
        if internal_link_candidates.any?
          "#{article_title}に実在する関連記事・店舗ページへの内部リンクを追加する"
        else
          "#{article_title}の内部リンク先候補を特定する"
        end
      when "content_update"
        "#{article_title}の本文構成と最新性を確認して更新する"
      when "shop_addition"
        shop_candidates.any? ? "#{article_title}の掲載候補店舗をDBから確認する" : "#{article_title}の未掲載店舗候補を特定する"
      when "verified_shop_addition"
        unverified_shop_candidates.any? ? "#{article_title}の未確認店舗の喫煙条件を確認する" : "#{article_title}の確認対象店舗を特定する"
      else
        "#{article_title}の実績を継続観測する"
      end
    end

    def description_for(brief)
      state = brief["current_state"]
      execution = brief["execution"]
      [
        "対象: #{article_path || '未特定'}",
        "現状: 表示#{dash(state['impressions'])} / CTR#{dash(state['ctr'])} / 順位#{dash(state['average_position'])}",
        "優先理由: #{short_reason}",
        "次: #{execution['suggested_next_action']}",
        "実行者: #{execution['executor_type']}"
      ].join("。").truncate(300)
    end

    def execution_prompt_for(brief)
      [
        "対象: #{brief.dig('target', 'target_url') || brief.dig('target', 'article_path') || '未特定'}",
        "次にやること: #{brief.dig('execution', 'suggested_next_action')}",
        "完了条件:",
        *brief["completion_conditions"].first(6).map { |condition| "- #{condition}" },
        "禁止: #{brief.dig('safety', 'prohibited_actions').first(3).join(' / ')}"
      ].join("\n")
    end

    def executor_type(codex_eligible:, human_required:, research_required:)
      return "research_then_codex" if research_required && CODEX_POSSIBLE_TYPES.include?(opportunity_type)
      return "human" if human_required
      return "codex_then_human_review" if codex_eligible

      "unavailable"
    end

    def suggested_next_action(changes, missing)
      return missing.first if missing.any?

      changes.first&.dig("instruction").presence || opportunity["next_action"].presence || "詳細を確認する"
    end

    def execution_readiness_for(brief)
      return "needs_target" if brief.dig("target", "target_type") != "existing_article"
      return "needs_query" if opportunity_type.in?(%w[ctr_improvement rank_improvement]) && top_queries.empty?
      return "needs_owner" if brief.dig("execution", "human_required")
      return "needs_target" if brief.dig("execution", "research_required")

      brief.dig("execution", "codex_eligible") ? "ready" : "blocked"
    end

    def target_type
      return "existing_article" if article_path.to_s.start_with?("/articles/")
      return "invalid_target" if article_path.blank?

      "article_not_found"
    end

    def target_url
      return unless target_type == "existing_article"

      "#{SUELOG_HOST}#{article_path}"
    end

    def article_path
      payload["normalized_path"].presence || payload["article_url"].to_s[%r{/articles/[^?#]+}]
    end

    def article_title
      article_metrics["title"].presence || payload["slug"].to_s.presence || article_path.to_s
    end

    def current_article_title
      article_record_value(%w[title]) || article_title
    end

    def current_meta_description
      article_record_value(%w[meta_description seo_description description])
    end

    def article_record_value(columns)
      record = article_record
      return unless record

      columns.each do |column|
        next unless record.respond_to?(column)

        value = record.public_send(column)
        return value if value.present?
      end
      nil
    rescue StandardError
      nil
    end

    def article_record
      return @article_record if defined?(@article_record)

      @article_record = if defined?(::Suelog::Article) && payload["article_id"].present?
        ::Suelog::Article.where(id: payload["article_id"]).first
      end
    rescue StandardError
      @article_record = nil
    end

    def gsc_metrics = payload["gsc"].to_h
    def ga4_metrics = payload["ga4"].to_h
    def shop_click_metrics = payload["shop_click"].to_h
    def article_metrics = payload["article"].to_h
    def relative_metrics = payload.dig("score_diagnostics", "business_relative").to_h

    def top_queries
      Array(gsc_metrics["top_queries"]).filter_map do |row|
        query = row.to_h["query"].to_s.squish
        next if query.blank?

        row.to_h.slice("query", "impressions", "clicks", "ctr", "average_position", "position")
      end.first(5)
    end

    def internal_link_candidates
      @internal_link_candidates ||= AicooDataSnapshot
        .where(source_type: "article_analytics")
        .where.not(id: snapshot.id)
        .recent
        .filter_map do |row|
          candidate_payload = row.payload.to_h.deep_stringify_keys
          next unless candidate_payload["business_id"].to_i == business.id
          path = candidate_payload["normalized_path"].to_s
          next unless path.start_with?("/articles/")

          {
            "article_id" => candidate_payload["article_id"],
            "title" => candidate_payload.dig("article", "title").presence || candidate_payload["slug"],
            "path" => path,
            "url" => "#{SUELOG_HOST}#{path}",
            "reason" => "同じBusinessの公開記事Snapshot"
          }
        end.first(5)
    rescue StandardError
      []
    end

    def shop_candidates
      @shop_candidates ||= begin
        return [] unless defined?(::Suelog::Shop)

        scope = ::Suelog::Shop.approved
        area = article_metrics["area"].to_s.squish
        genre = article_metrics["genre"].to_s.squish
        scope = scope.where("area ILIKE ?", "%#{area}%") if area.present? && ::Suelog::Shop.column_names.include?("area")
        scope = scope.where("genre ILIKE ?", "%#{genre}%") if genre.present? && ::Suelog::Shop.column_names.include?("genre")
        scope.limit(5).map do |shop|
          {
            "shop_id" => shop.id,
            "name" => shop.name,
            "area" => shop.try(:area),
            "genre" => shop.try(:genre),
            "smoking_area" => shop.try(:smoking_area_label),
            "smoking_type" => shop.try(:smoking_type_label)
          }.compact
        end
      end
    rescue StandardError
      []
    end

    def unverified_shop_candidates
      @unverified_shop_candidates ||= begin
        return [] unless defined?(::Suelog::Shop)

        scope = ::Suelog::Shop.verification_needed
        area = article_metrics["area"].to_s.squish
        genre = article_metrics["genre"].to_s.squish
        scope = scope.where("area ILIKE ?", "%#{area}%") if area.present? && ::Suelog::Shop.column_names.include?("area")
        scope = scope.where("genre ILIKE ?", "%#{genre}%") if genre.present? && ::Suelog::Shop.column_names.include?("genre")
        scope.limit(5).map do |shop|
          {
            "shop_id" => shop.id,
            "name" => shop.name,
            "area" => shop.try(:area),
            "genre" => shop.try(:genre),
            "last_confirmed_on" => shop.try(:last_confirmed_on)&.iso8601,
            "smoking_area" => shop.try(:smoking_area_label),
            "smoking_type" => shop.try(:smoking_type_label)
          }.compact
        end
      end
    rescue StandardError
      []
    end

    def shop_candidate_filter
      {
        "area" => article_metrics["area"],
        "genre" => article_metrics["genre"],
        "source" => "Suelog::Shop.approved"
      }
    end

    def verification_fields
      %w[喫煙可否 紙タバコ可否 席で吸えるか 加熱式限定か 喫煙室のみか 営業状態]
    end

    def target_shop_count
      current = article_metrics["shop_count"].to_i
      current.positive? ? [ current + shop_shortage_count, 5 ].max : nil
    end

    def shop_shortage_count
      current = article_metrics["shop_count"].to_i
      [5 - current, 0].max
    end

    def unverified_shop_count
      shop_count = article_metrics["shop_count"].to_i
      verified = article_metrics["verified_shop_count"].to_i
      [shop_count - verified, 0].max
    end

    def expected_click_gain
      gsc = gsc_metrics
      impressions = decimal(gsc["impressions"])
      ctr = decimal(gsc["ctr"])
      position = decimal(gsc["average_position"])
      return nil unless impressions.positive? && ctr >= 0

      target = if position.positive? && position <= 5
        0.04.to_d
      elsif position.positive? && position <= 10
        0.03.to_d
      elsif position.positive? && position <= 20
        0.02.to_d
      else
        0.012.to_d
      end
      [(impressions * [target - ctr, 0.to_d].max).round(2).to_f, 0].max
    end

    def expected_ctr_range
      current = decimal(gsc_metrics["ctr"])
      return nil unless current >= 0

      [current.to_f.round(4), (current + 0.005.to_d).to_f.round(4)]
    end

    def expected_position_range
      position = decimal(gsc_metrics["average_position"])
      return nil unless position.positive?

      [ [position - 3, 1].max.to_f.round(1), position.to_f.round(1) ]
    end

    def data_confidence
      available = [gsc_metrics, ga4_metrics, shop_click_metrics].count { |row| row["available"] == true }
      case available
      when 3 then "high"
      when 2 then "medium"
      else "low"
      end
    end

    def short_reason
      opportunity["ranking_reason"].to_s.presence ||
        analyzer_evidence["seo_reason"].to_s.presence ||
        analyzer_evidence["ctr_reason"].to_s.presence ||
        "#{opportunity['label']} Opportunity"
    end

    def nullable_number(value)
      return nil if value.nil?
      return nil if value.to_s == ""

      value
    end

    def decimal(value)
      return 0.to_d if value.nil? || value.to_s.blank?

      BigDecimal(value.to_s)
    rescue ArgumentError
      0.to_d
    end

    def format_value(value)
      return "-" if value.blank?

      value.to_f.round(1)
    end

    def dash(value)
      value.nil? || value.to_s.blank? ? "-" : value
    end

    def opportunity_type
      opportunity["opportunity_type"].to_s
    end
  end
end
