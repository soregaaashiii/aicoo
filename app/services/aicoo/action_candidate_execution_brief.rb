module Aicoo
  class ActionCandidateExecutionBrief
    attr_reader :action_candidate

    def initialize(action_candidate)
      @action_candidate = action_candidate
    end

    def target
      {
        business: business&.name || "-",
        url: target_url.presence || "未特定",
        admin_url: admin_url.presence || "未特定",
        resource_type: resource_type,
        resource_name: resource_name,
        edit_url: edit_url.presence || "未特定",
        candidate_pages: candidate_pages
      }
    end

    def open_links
      [
        [ "記事を開く", target_url ],
        [ "管理画面を開く", admin_url ],
        [ "編集する", edit_url ]
      ].filter_map do |label, url|
        next if url.blank?

        { label:, url: }
      end
    end

    def before_after_items
      @before_after_items ||= [
        item("SEOタイトル", current_title, proposed_title),
        item("meta description", current_meta_description, proposed_meta_description),
        item("H1", current_h1, proposed_h1),
        item("冒頭文", current_intro, proposed_intro),
        item("CTA", current_cta, proposed_cta),
        item("FAQ", current_faq, proposed_faq),
        item("内部リンク", current_internal_links, proposed_internal_links)
      ]
    end

    def serp_comparison
      {
        query: source_query.presence || "未特定",
        top_results: serp_results,
        common_words: common_words,
        common_structure: common_structure,
        missing_elements: missing_elements,
        reason: reason
      }
    end

    def file_changes
      @file_changes ||= explicit_file_changes.presence || inferred_file_changes
    end

    def completion_criteria
      explicit_completion_criteria.presence || [
        "#{proposed_title} にSEOタイトルが変更されていること",
        "meta descriptionが変更案どおりに更新されていること",
        "冒頭文に対象検索意図と主要語が入っていること",
        "比較・掲載件数・口コミなど不足要素のうち最低1つが追加されていること",
        "FAQが2件以上追加または更新されていること",
        "ActionResultに変更内容と確認URLが登録されていること"
      ]
    end

    def expected_effects
      {
        ctr: metadata["expected_ctr_delta"].presence || "+0.8%",
        rank: metadata["expected_rank_delta"].presence || "+2.3位",
        profit: expected_profit_label,
        hourly: expected_hourly_label
      }
    end

    def expected_minutes
      expansion["expected_minutes"].presence || metadata["expected_minutes"].presence || minutes_from_hours || 30
    end

    def prompt_markdown
      <<~MARKDOWN.strip
        # ActionCandidate実行指示書

        ## 目的
        #{action_candidate.title}

        ## 対象
        - Business: #{target[:business]}
        - URL: #{target[:url]}
        - 管理画面URL: #{target[:admin_url]}
        - 対象: #{target[:resource_type]} #{target[:resource_name]}
        - 候補ページ: #{target[:candidate_pages].presence&.join(", ") || "未特定"}

        ## 現在 → 変更後
        #{before_after_items.map { |row| "- #{row[:label]}\n  - 現在: #{row[:current]}\n  - 変更後: #{row[:after]}" }.join("\n")}

        ## SERP差分
        - 根拠検索クエリ: #{serp_comparison[:query]}
        - 共通ワード: #{serp_comparison[:common_words].join(", ")}
        - 共通構成: #{serp_comparison[:common_structure].join(", ")}
        - 不足要素: #{serp_comparison[:missing_elements].join(", ")}
        - 修正理由: #{serp_comparison[:reason]}

        ## 変更ファイル
        #{file_changes.map { |path| "- #{path}" }.join("\n")}

        ## 完了条件
        #{completion_criteria.map { |criterion| "- #{criterion}" }.join("\n")}

        ## 期待効果
        - CTR: #{expected_effects[:ctr]}
        - 順位: #{expected_effects[:rank]}
        - 期待利益: #{expected_effects[:profit]}
        - 期待時給: #{expected_effects[:hourly]}
      MARKDOWN
    end

    def openai_context
      {
        business: business&.slice(:id, :name, :business_type, :category, :status),
        action_candidate: action_candidate.slice(:id, :title, :action_type, :generation_source, :evaluation_reason, :execution_prompt),
        serp: serp_comparison,
        ga4_gsc_evidence: metadata.dig("evidence", "items") || [],
        learning: metadata["business_playbook"] || {},
        action_history: metadata["execution_feasibility_correction"] || {},
        expected_effects:
      }
    end

    private

    def business
      action_candidate.business
    end

    def metadata
      @metadata ||= action_candidate.metadata.to_h
    end

    def expansion
      @expansion ||= metadata["action_expansion"].to_h
    end

    def evidence_items
      @evidence_items ||= Array(metadata.dig("evidence", "items"))
    end

    def item(label, current, after)
      { label:, current: current.presence || "未設定", after: after.presence || "変更不要" }
    end

    def source_query
      metadata["source_query"].presence ||
        metadata["serp_keyword"].presence ||
        expansion["target_keyword"].presence ||
        evidence_items.filter_map { |row| row["keyword"].presence }.first
    end

    def target_url
      raw = metadata["target_url"].presence ||
        expansion["target_url"].presence ||
        evidence_items.filter_map { |row| row["page"].presence || row["url"].presence }.first
      Aicoo::ActionTargetUrlResolver.call(raw, require_known_route: true)
    end

    def admin_url
      metadata["admin_url"].presence ||
        metadata["edit_url"].presence ||
        (target_url.present? ? target_url : nil)
    end

    def edit_url
      metadata["edit_url"].presence || admin_url
    end

    def resource_type
      metadata["resource_type"].presence || inferred_resource_type
    end

    def resource_name
      metadata["resource_name"].presence || target_url.presence || source_query.presence || action_candidate.title
    end

    def candidate_pages
      explicit = Array(metadata["candidate_pages"] || expansion["candidate_pages"]).compact_blank
      return explicit if explicit.any?

      if metric_target_reference?
        [ "店舗詳細ページ", "地図ページ", "記事内店舗カード" ]
      else
        [ "関連ページを特定してください" ]
      end
    end

    def metric_target_reference?
      [
        metadata["target_url"],
        expansion["target_url"],
        metadata["source_metric"],
        metadata["metric_name"],
        evidence_items.filter_map { |row| row["metric_name"].presence }
      ].flatten.compact.any? { |value| Aicoo::ActionTargetUrlResolver.metric_reference?(value) }
    end

    def inferred_resource_type
      text = [ action_candidate.title, action_candidate.description, target_url ].compact.join(" ")
      return "Article" if text.match?(/記事|blog|article/i)
      return "LP" if text.match?(/lp|landing/i)

      "Business"
    end

    def current_title
      metadata["current_title"].presence || expansion["current_title"].presence || "#{business&.name}｜#{source_query.presence || action_candidate.title}"
    end

    def proposed_title
      metadata["proposed_title"].presence ||
        expansion["proposed_title"].presence ||
        "【#{Date.current.year}年版】#{source_query.presence || action_candidate.title}｜#{business&.name}"
    end

    def current_meta_description
      metadata["current_meta_description"].presence || action_candidate.description.presence || "未設定"
    end

    def proposed_meta_description
      metadata["proposed_meta_description"].presence ||
        "#{source_query.presence || action_candidate.title}を探す人向けに、比較・料金・口コミ・掲載件数を整理。#{business&.name}で次に取るべき行動まで確認できます。"
    end

    def current_h1
      metadata["current_h1"].presence || current_title
    end

    def proposed_h1
      metadata["proposed_h1"].presence || proposed_title.sub(/\A【[^】]+】/, "")
    end

    def current_intro
      metadata["current_intro"].presence || "検索意図に対する冒頭説明が不足しています。"
    end

    def proposed_intro
      metadata["proposed_intro"].presence ||
        "#{source_query.presence || action_candidate.title}を探している人が最初に比較したいポイントを、料金・口コミ・掲載件数・選び方の順に整理します。迷わず次の行動に進めるよう、冒頭で結論とおすすめ条件を提示します。"
    end

    def current_cta
      metadata["current_cta"].presence || "詳細を見る"
    end

    def proposed_cta
      metadata["proposed_cta"].presence || "条件に合う候補を今すぐ確認する"
    end

    def current_faq
      metadata["current_faq"].presence || "FAQ未設置、または検索意図に対する回答が不足しています。"
    end

    def proposed_faq
      metadata["proposed_faq"].presence ||
        "Q. #{source_query.presence || 'この条件'}で選ぶ時に最初に見るべき点は？\nA. 料金・口コミ・対応範囲・掲載件数を比較し、目的に合う候補から確認してください。"
    end

    def current_internal_links
      metadata["current_internal_links"].presence || "関連ページへの内部リンクが不足しています。"
    end

    def proposed_internal_links
      metadata["proposed_internal_links"].presence || "関連する比較ページ、料金ページ、口コミページ、エリア/カテゴリページへ3〜5件リンクを追加する。"
    end

    def serp_results
      explicit = Array(metadata["serp_top_results"])
      return explicit.first(5) if explicit.any?

      return [] if source_query.blank? || business.blank?

      SerpAnalysis
        .where(business:, keyword: source_query)
        .order(analyzed_at: :desc)
        .includes(:serp_results)
        .first
        &.serp_results
        &.order(:position)
        &.limit(5)
        &.map { |row| { "position" => row.position, "title" => row.title, "url" => row.url, "snippet" => row.snippet } } || []
    end

    def common_words
      explicit = Array(metadata["serp_common_words"])
      return explicit if explicit.any?

      titles = serp_results.map { |row| row["title"].to_s }
      words = %w[比較 料金 口コミ 掲載件数 おすすめ 事例 選び方 ランキング]
      found = words.select { |word| titles.any? { |title| title.include?(word) } }
      found.presence || %w[比較 料金 口コミ 掲載件数]
    end

    def common_structure
      explicit = Array(metadata["serp_common_structure"])
      return explicit if explicit.any?

      %w[結論 比較表 選び方 FAQ CTA]
    end

    def missing_elements
      explicit = Array(metadata["missing_elements"])
      return explicit if explicit.any?

      %w[比較 掲載件数 FAQ 内部リンク]
    end

    def reason
      metadata["revision_reason"].presence ||
        action_candidate.evaluation_reason.presence ||
        "比較という検索意図が強いため、比較表・掲載件数・FAQを追加して判断材料を増やしてください。"
    end

    def explicit_file_changes
      Array(metadata["target_files"] || metadata["changed_files"]).compact_blank
    end

    def inferred_file_changes
      case resource_type
      when "Article"
        %w[
          app/views/articles/show.html.erb
          app/controllers/articles_controller.rb
          app/services/article_seo_presenter.rb
        ]
      when "LP"
        %w[
          app/views/public_landing_pages/show.html.erb
          app/services/aicoo/lp_content_builder.rb
          app/controllers/public_landing_pages_controller.rb
        ]
      else
        %w[
          app/views/businesses/show.html.erb
          app/services/aicoo/action_candidate_execution_brief.rb
        ]
      end
    end

    def explicit_completion_criteria
      Array(metadata["completion_criteria"] || expansion["completion_criteria"]).compact_blank
    end

    def expected_profit_label
      value = action_candidate.expected_profit_yen || action_candidate.final_expected_value_yen || action_candidate.immediate_value_yen
      value.present? ? "¥#{value.to_i.to_fs(:delimited)}/月" : "+4,200円/月"
    end

    def expected_hourly_label
      value = action_candidate.expected_hourly_value_yen
      value.present? ? "¥#{value.to_i.to_fs(:delimited)}" : "¥8,500"
    end

    def minutes_from_hours
      return if action_candidate.expected_hours.blank?

      (action_candidate.expected_hours.to_d * 60).round
    end
  end
end
