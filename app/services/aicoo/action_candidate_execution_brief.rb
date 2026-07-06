module Aicoo
  class ActionCandidateExecutionBrief
    attr_reader :action_candidate

    def initialize(action_candidate)
      @action_candidate = action_candidate
    end

    def target
      {
        business: business&.name || "-",
        url: target_url.presence || (new_article_creation? ? new_article_spec[:url] : "未特定"),
        admin_url: admin_url.presence || (new_article_creation? ? new_article_spec[:admin_url] : "未特定"),
        resource_type: resource_type,
        resource_name: resource_name,
        edit_url: edit_url.presence || (new_article_creation? ? new_article_spec[:edit_url] : "未特定"),
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
      return [] if content_creation_execution?

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
        relevance: serp_relevance_summary,
        common_words: common_words,
        common_structure: common_structure,
        missing_elements: missing_elements,
        reason: reason
      }
    end

    def file_changes
      return [] unless action_candidate.code_revision_execution_mode?

      @file_changes ||= explicit_file_changes.presence || inferred_file_changes
    end

    def completion_criteria
      return [] if content_creation_execution?
      return new_article_completion_criteria if new_article_creation? && explicit_completion_criteria.blank?

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

    def content_creation_execution?
      action_candidate.execution_mode == "content_creation"
    end

    def article_plan
      @article_plan ||= {
        title: recommended_article_title,
        keyword: search_query,
        article_type: article_type,
        target_user: target_user,
        search_intent: search_intent,
        reason: reason,
        expected_profit: expected_effects[:profit],
        priority: action_candidate.final_score.to_i,
        recommended_sections: recommended_sections,
        related_pages: related_pages,
        internal_links: article_internal_link_targets,
        evidence: {
          source: Array(metadata.dig("analyzer_evidence", "source") || metadata.dig("evidence", "source")),
          query: search_query,
          current_value: metadata["current_value"],
          benchmark_value: metadata["benchmark_value"],
          expected_ctr: expected_effects[:ctr],
          expected_rank: expected_effects[:rank]
        }.compact
      }
    end

    def search_query
      source_query.presence || "未特定"
    end

    def top_serp_results
      serp_results.first(5)
    end

    def own_site_gap
      return branded_search_gap if branded_search_page_needed?

      missing = serp_comparison[:missing_elements]
      common = serp_comparison[:common_words]
      [
        common.present? && "上位サイトは #{common.join("・")} を訴求しています。",
        missing.present? && "#{business&.name || '自サイト'}には #{missing.join("・")} が不足しています。",
        "差分を踏まえて、記事生成AIへ渡す推奨構成だけを決めます。"
      ].compact.join("\n")
    end

    def page_change_type
      case metadata["work_type"].to_s
      when "existing_page_improvement" then return "既存ページ改善"
      when "new_article" then return "新規記事"
      when "new_lp" then return "新規LP"
      when "new_category" then return "新規カテゴリ"
      when "search_intent_analysis" then return "検索意図分析"
      when "competitor_analysis" then return "競合分析"
      when "data_shortage" then return "データ不足確認"
      end

      return "新規記事" if new_article_creation?
      return "新規LP" if action_candidate.action_type.in?(%w[build_lp lp_experiment])
      return "既存記事" if resource_type == "Article"
      return "既存ページ" if target_url.present?

      "未特定"
    end

    def article_id
      return "新規作成" if new_article_creation?

      metadata["article_id"].presence ||
        metadata["resource_id"].presence ||
        metadata.dig("article", "id").presence ||
        expansion["article_id"].presence
    end

    def ranked_candidate_pages
      candidate_pages.each_with_index.map do |page, index|
        {
          rank: index + 1,
          page:,
          reason: candidate_page_reason(page, index)
        }
      end
    end

    def new_article_spec
      @new_article_spec ||= {
        slug: recommended_slug,
        title: recommended_article_title,
        seo_title: proposed_title,
        meta_description: proposed_meta_description,
        h1: proposed_h1,
        url: recommended_article_url,
        route: "GET /articles/:slug",
        admin_url: recommended_article_admin_url,
        edit_url: recommended_article_edit_url,
        model: "Article",
        structure: article_structure,
        cta: proposed_cta,
        internal_links: article_internal_link_targets,
        implementation_note: article_creation_implementation_note
      }
    end

    def codex_patch_text
      return "AICOOは本文を生成しません。記事生成AIまたは記事作成フローへ記事計画を渡してください。" if content_creation_execution?

      base = before_after_items.map do |row|
        <<~TEXT.strip
          #{row[:label]}:
          現在:
          #{row[:current]}

          修正後:
          #{row[:after]}
        TEXT
      end.join("\n\n")

      return base unless new_article_creation?

      <<~TEXT.strip
        #{base}

        新規Article作成:
        slug: #{new_article_spec[:slug]}
        title: #{new_article_spec[:title]}
        seo_title: #{new_article_spec[:seo_title]}
        meta_description: #{new_article_spec[:meta_description]}
        url: #{new_article_spec[:url]}
        route: #{new_article_spec[:route]}

        記事構成:
        #{new_article_spec[:structure].map { |row| "- #{row[:level]} #{row[:text]}" }.join("\n")}

        注意:
        AICOOは本文を生成しません。
        必要な本文は記事生成AIへ記事計画を渡して作成してください。
      TEXT
    end

    def prompt_markdown
      return content_plan_markdown if content_creation_execution?

      <<~MARKDOWN.strip
        # ActionCandidate実行指示書

        ## 目的
        #{action_candidate.title}

        ## 対象
        - Business: #{target[:business]}
        - URL: #{target[:url]}
        - 管理画面URL: #{target[:admin_url]}
        - 対象: #{target[:resource_type]} #{target[:resource_name]}
        - 記事ID: #{article_id.presence || "未特定"}
        - 新規/既存: #{page_change_type}
        - 候補ページ: #{target[:candidate_pages].presence&.join(", ") || "未特定"}

        #{competitor_reference_markdown}

        #{new_article_creation? ? new_article_prompt_section : nil}

        ## ① 検索クエリ
        #{search_query}

        ## ② SERP上位5件
        #{top_serp_results.any? ? top_serp_results.map { |row| "- #{row['position'] || '-'}位 #{row['title']} #{row['url']}\n  #{row['snippet']}" }.join("\n") : "- 未取得"}

        ## SERP関連度
        - 判定: #{serp_comparison[:relevance][:status]}
        - 関連SERP: #{serp_comparison[:relevance][:relevant_count]}件 / 取得#{serp_comparison[:relevance][:total_count]}件
        - 除外SERP: #{serp_comparison[:relevance][:excluded_count]}件
        - 除外理由: #{serp_comparison[:relevance][:excluded_reasons].presence&.join(" / ") || "なし"}
        - 方針: #{serp_comparison[:relevance][:guidance]}

        ## ③ 上位サイト共通要素
        - 共通ワード: #{serp_comparison[:common_words].join(", ")}
        - 共通構成: #{serp_comparison[:common_structure].join(", ")}

        ## ④ 自サイトとの差分
        #{own_site_gap}

        ## ⑤ 改善対象ページ
        - URL: #{target[:url]}
        - Business: #{target[:business]}
        - 記事ID: #{article_id.presence || "未特定"}
        - 候補ページ:
        #{ranked_candidate_pages.map { |row| "  #{row[:rank]}. #{row[:page]} - #{row[:reason]}" }.join("\n")}

        ## ⑥ 新規記事か既存記事か
        #{page_change_type}

        ## SERP差分
        - 根拠検索クエリ: #{serp_comparison[:query]}
        - SERP関連度: #{serp_comparison[:relevance][:status]}（関連#{serp_comparison[:relevance][:relevant_count]}/取得#{serp_comparison[:relevance][:total_count]}）
        - 共通ワード: #{serp_comparison[:common_words].join(", ")}
        - 共通構成: #{serp_comparison[:common_structure].join(", ")}
        - 不足要素: #{serp_comparison[:missing_elements].join(", ")}
        - 修正理由: #{serp_comparison[:reason]}

        ## 期待効果
        - 期待CTR: #{expected_effects[:ctr]}
        - 期待順位: #{expected_effects[:rank]}
        - 期待利益: #{expected_effects[:profit]}
        - 期待時給: #{expected_effects[:hourly]}

        ## 分離方針
        - AICOOは判断だけを保持します。
        - 本文や長大なCodex Promptは生成しません。
        - 実装や記事作成が必要な場合は、別コンポーネントへこの判断情報を渡します。
      MARKDOWN
    end

    def content_plan_markdown
      plan = article_plan
      <<~MARKDOWN.strip
        # ActionCandidate 記事計画

        ## AICOOの判断
        #{action_candidate.title}

        ## 記事タイトル
        #{plan[:title]}

        ## 検索キーワード
        #{plan[:keyword]}

        ## 記事タイプ
        #{plan[:article_type]}

        ## ターゲット
        #{plan[:target_user]}

        ## 検索意図
        #{plan[:search_intent]}

        ## 理由
        #{plan[:reason]}

        ## 期待効果
        - 期待CTR: #{expected_effects[:ctr]}
        - 期待順位: #{expected_effects[:rank]}
        - 期待利益: #{expected_effects[:profit]}

        #{competitor_reference_markdown}

        ## 推奨構成
        #{plan[:recommended_sections].map { |section| "- #{section}" }.join("\n")}

        ## 関連ページ
        #{plan[:related_pages].map { |page| "- #{page}" }.join("\n")}

        ## 内部リンク候補
        #{plan[:internal_links].map { |path| "- #{path}" }.join("\n")}

        ## 分離方針
        - AICOOは記事本文を生成しません。
        - 本文や長文修正文は保持しません。
        - 記事を書く場合は、この記事計画を記事生成AIへ渡してください。
        - Codexを使う場合はArticle作成・DB登録・公開・内部リンク更新だけを対象にします。
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

    def competitor_reference_markdown
      return nil if competitor_urls.blank? && competitor_features.blank? && reference_missing_features.blank?

      <<~MARKDOWN.strip
        ## 参考競合
        - 参考URL: #{competitor_urls.presence&.join(", ") || "未取得"}
        - 競合の良い点: #{competitor_features.presence&.join(", ") || "未取得"}
        - 自社に取り入れる不足要素: #{reference_missing_features.presence&.join(", ") || "未取得"}
        - 改善理由: #{metadata["improvement_reason"].presence || "競合は改善対象ではなく、自社ページ改善の参考情報として扱います。"}
      MARKDOWN
    end

    def competitor_urls
      Array(metadata["competitor_urls"]).compact_blank
    end

    def competitor_features
      Array(metadata["competitor_features"]).compact_blank
    end

    def reference_missing_features
      Array(metadata["missing_features"]).compact_blank
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
      return nil if Aicoo::ActionTargetUrlResolver.metric_reference?(raw)

      resolved = Aicoo::ActionTargetUrlResolver.call(raw, require_known_route: true)
      return nil if resolved.blank?

      Aicoo::BusinessOwnedUrlPolicy.call(business:, url: resolved).url
    end

    def target_url_type
      raw = metadata["target_url"].presence ||
        expansion["target_url"].presence ||
        evidence_items.filter_map { |row| row["page"].presence || row["url"].presence }.first
      return "unknown" if raw.blank? || Aicoo::ActionTargetUrlResolver.metric_reference?(raw)

      resolved = Aicoo::ActionTargetUrlResolver.call(raw, require_known_route: true)
      return "unknown" if resolved.blank?

      Aicoo::BusinessOwnedUrlPolicy.call(business:, url: resolved).target_url_type
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
      return "Article" if new_article_creation?

      metadata["resource_type"].presence || inferred_resource_type
    end

    def resource_name
      return new_article_spec[:title] if new_article_creation?

      metadata["resource_name"].presence || target_url.presence || source_query.presence || action_candidate.title
    end

    def new_article_creation?
      branded_search_page_needed? ||
        action_candidate.action_type == "seo_article" ||
        expansion["expansion_type"] == "content_area_expansion"
    end

    def recommended_slug
      metadata["recommended_slug"].presence ||
        expansion["recommended_slug"].presence ||
        (branded_search_page_needed? && suelog_business? ? "suelog-comparison" : fallback_article_slug)
    end

    def recommended_article_title
      metadata["recommended_title"].presence ||
        expansion["recommended_title"].presence ||
        (branded_search_page_needed? && suelog_business? ? "吸えログとは？食べログ・Googleマップ・Rettyとの違い" : proposed_h1)
    end

    def recommended_article_url
      "/articles/#{recommended_slug}"
    end

    def recommended_article_admin_url
      "/admin/articles/new?slug=#{recommended_slug}"
    end

    def recommended_article_edit_url
      "/admin/articles/#{recommended_slug}/edit"
    end

    def article_structure
      if branded_search_page_needed? && suelog_business?
        [
          { level: "H1", text: "吸えログとは？食べログ・Googleマップ・Rettyとの違い" },
          { level: "H2", text: "吸えログでできること" },
          { level: "H2", text: "食べログ・Googleマップ・Rettyとの違い" },
          { level: "H2", text: "比較表" },
          { level: "H2", text: "吸えログが向いている人" },
          { level: "H2", text: "大阪で喫煙できる店を探す" },
          { level: "H3", text: "梅田で喫煙できる店" },
          { level: "H3", text: "難波で喫煙できる店" },
          { level: "H3", text: "喫煙できるカフェ・居酒屋" },
          { level: "H2", text: "FAQ" }
        ]
      else
        [
          { level: "H1", text: proposed_h1 },
          { level: "H2", text: "#{search_query}の結論" },
          { level: "H2", text: "比較表" },
          { level: "H2", text: "選び方" },
          { level: "H2", text: "よくある質問" }
        ]
      end
    end

    def article_internal_link_targets
      if branded_search_page_needed? && suelog_business?
        [
          "/osaka",
          "/umeda",
          "/namba",
          "/categories/cafe",
          "/categories/izakaya"
        ]
      else
        candidate_pages
      end
    end

    def article_creation_implementation_note
      "対象プロジェクトの既存Article作成フローを確認し、admin導線・service・taskのいずれか既存の方法で実データを登録する。新規routeやseed追加は、既存Article作成フローに必要な場合だけ行う。記事テンプレートだけで終わらせず、slug/title/seo_title/meta_description/body/statusを保存する。"
    end

    def new_article_completion_criteria
      [
        "Article slug=#{new_article_spec[:slug]} が作成されている",
        "#{new_article_spec[:url]} で公開確認できる",
        "SEO title/meta description/H1 が設定されている",
        "比較表が本文内にある",
        "FAQが本文内にある",
        "#{new_article_spec[:internal_links].join(' ')} への内部リンクがある",
        "CTA「#{new_article_spec[:cta]}」が表示される",
        "ActionResult登録用の変更メモが生成される"
      ]
    end

    def new_article_prompt_section
      <<~MARKDOWN.strip
        ## 新規記事作成仕様
        - 推奨slug: #{new_article_spec[:slug]}
        - 推奨title: #{new_article_spec[:title]}
        - 推奨SEO title: #{new_article_spec[:seo_title]}
        - meta description: #{new_article_spec[:meta_description]}
        - H1: #{new_article_spec[:h1]}
        - URL: #{new_article_spec[:url]}
        - 作成対象モデル: #{new_article_spec[:model]}
        - 作成対象route: #{new_article_spec[:route]}
        - 管理画面URL候補: #{new_article_spec[:admin_url]}
        - 編集URL候補: #{new_article_spec[:edit_url]}

        ### 記事構成
        #{new_article_spec[:structure].map { |row| "- #{row[:level]} #{row[:text]}" }.join("\n")}

        ### CTA
        #{new_article_spec[:cta]}

        ### 内部リンク先候補
        #{new_article_spec[:internal_links].map { |path| "- #{path}" }.join("\n")}

        ### 分離方針
        AICOOは本文を生成しません。
      MARKDOWN
    end

    def article_type
      metadata["article_type"].presence || inferred_article_type
    end

    def inferred_article_type
      return "comparison" if branded_search_page_needed? || search_query.match?(/比較|違い/)
      return "area" if search_query.match?(/大阪|梅田|難波|福島|天王寺/)
      return "genre" if search_query.match?(/居酒屋|カフェ|バー|焼肉|ランチ/)
      return "faq" if search_query.match?(/とは|方法|できる/)

      "guide"
    end

    def target_user
      return metadata["target_user"] if metadata["target_user"].present?

      if branded_search_page_needed?
        "初めて#{business&.name}を知った人"
      elsif search_query.match?(/喫煙|タバコ|煙草/)
        "大阪で喫煙できる店を探したい人"
      else
        "検索キーワードに合う選択肢を比較したい人"
      end
    end

    def search_intent
      return metadata["search_intent"] if metadata["search_intent"].present?

      if article_type == "comparison"
        "比較したい"
      elsif article_type == "area"
        "探したい"
      elsif article_type == "faq"
        "違いを知りたい"
      else
        "おすすめを知りたい"
      end
    end

    def recommended_sections
      explicit = Array(metadata["recommended_sections"]).compact_blank
      return explicit if explicit.any?

      article_structure.map { |row| row[:text] }.uniq
    end

    def related_pages
      Array(metadata["related_pages"]).presence || candidate_pages
    end

    def candidate_pages
      explicit = Array(metadata["candidate_pages"] || expansion["candidate_pages"]).compact_blank
      return explicit if explicit.any?

      if branded_search_page_needed?
        return [
          "#{business&.name}とは何か",
          "食べログ/Googleマップ/Rettyとの違い",
          "大阪で喫煙できる店探しに特化した比較ページ"
        ]
      end

      if metric_target_reference?
        [ "店舗詳細ページ", "地図ページ", "記事内店舗カード" ]
      else
        [ "関連ページを特定してください" ]
      end
    end

    def candidate_page_reason(page, index)
      base_score = [ "最も期待値が高い候補", "次点の候補", "補助候補" ][index] || "候補"
      return "#{base_score}。送客CTAとの距離が近いです。" if page.match?(/店舗|地図|カード/)
      return "#{base_score}。検索意図と本文改善を結びつけやすいです。" if page.match?(/記事|コンテンツ/)

      "#{base_score}。Business全体の導線改善に使えます。"
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
      return "未作成" if new_article_creation? && metadata["current_title"].blank? && expansion["current_title"].blank?
      return "#{business&.name}｜サービス説明ページ未作成" if branded_search_page_needed?

      metadata["current_title"].presence || expansion["current_title"].presence || "#{business&.name}｜#{source_query.presence || action_candidate.title}"
    end

    def proposed_title
      if branded_search_page_needed?
        return "#{business&.name}とは？食べログ・Googleマップ・Rettyとの違い｜大阪の喫煙店検索"
      end

      metadata["proposed_title"].presence ||
        expansion["proposed_title"].presence ||
        "【#{Date.current.year}年版】#{source_query.presence || action_candidate.title}｜#{business&.name}"
    end

    def current_meta_description
      return "未作成" if new_article_creation? && metadata["current_meta_description"].blank?

      metadata["current_meta_description"].presence || action_candidate.description.presence || "未設定"
    end

    def proposed_meta_description
      if branded_search_page_needed?
        return "#{business&.name}は大阪で喫煙できる飲食店・カフェ・居酒屋を探せる検索サービスです。食べログ、Googleマップ、Rettyとの違いと、紙タバコ・加熱式で探せる強みを整理します。"
      end

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
      return "未作成" if new_article_creation? && metadata["current_intro"].blank?

      metadata["current_intro"].presence || "検索意図に対する冒頭説明が不足しています。"
    end

    def proposed_intro
      if branded_search_page_needed?
        return "#{business&.name}は、喫煙できるお店を大阪・梅田・難波などのエリアから探したい人向けの検索サービスです。食べログやGoogleマップでは分かりにくい紙タバコ/加熱式の可否、喫煙可能な飲食店・居酒屋・カフェを、条件に合わせて確認できます。"
      end

      metadata["proposed_intro"].presence ||
        "#{source_query.presence || action_candidate.title}を探している人が最初に比較したいポイントを、料金・口コミ・掲載件数・選び方の順に整理します。迷わず次の行動に進めるよう、冒頭で結論とおすすめ条件を提示します。"
    end

    def current_cta
      return "未作成" if new_article_creation? && metadata["current_cta"].blank?

      metadata["current_cta"].presence || "詳細を見る"
    end

    def proposed_cta
      return "大阪で喫煙できるお店を探す" if branded_search_page_needed?

      metadata["proposed_cta"].presence || "条件に合う候補を今すぐ確認する"
    end

    def current_faq
      return "未作成" if new_article_creation? && metadata["current_faq"].blank?

      metadata["current_faq"].presence || "FAQ未設置、または検索意図に対する回答が不足しています。"
    end

    def proposed_faq
      if branded_search_page_needed?
        return "Q. #{business&.name}は何ができますか？\nA. 大阪の喫煙可能な飲食店・居酒屋・カフェを、エリアや喫煙条件から探せます。\n\nQ. 食べログやGoogleマップと何が違いますか？\nA. 喫煙可否、紙タバコ/加熱式、エリア別の探しやすさに絞っている点が違います。"
      end

      metadata["proposed_faq"].presence ||
        "Q. #{source_query.presence || 'この条件'}で選ぶ時に最初に見るべき点は？\nA. 料金・口コミ・対応範囲・掲載件数を比較し、目的に合う候補から確認してください。"
    end

    def current_internal_links
      return "未作成" if new_article_creation? && metadata["current_internal_links"].blank?

      metadata["current_internal_links"].presence || "関連ページへの内部リンクが不足しています。"
    end

    def proposed_internal_links
      if branded_search_page_needed?
        return "大阪、梅田、難波、喫煙可能カフェ、喫煙可能居酒屋の検索ページへ内部リンクを追加する。"
      end

      metadata["proposed_internal_links"].presence || "関連する比較ページ、料金ページ、口コミページ、エリア/カテゴリページへ3〜5件リンクを追加する。"
    end

    def serp_results
      return [] unless serp_allowed?

      relevant_serp_results_from(raw_serp_results).first(5)
    end

    def raw_serp_results
      return [] unless serp_allowed?

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
      return explicit if explicit.any? && serp_allowed?
      return [] unless serp_allowed?
      return %w[指名検索 食べログ Googleマップ Retty 喫煙店検索] if branded_search_page_needed?

      titles = serp_results.map { |row| row["title"].to_s }
      words = %w[比較 料金 口コミ 掲載件数 おすすめ 事例 選び方 ランキング]
      found = words.select { |word| titles.any? { |title| title.include?(word) } }
      found.presence || %w[比較 料金 口コミ 掲載件数]
    end

    def common_structure
      explicit = Array(metadata["serp_common_structure"])
      return explicit if explicit.any? && serp_allowed?
      return [] unless serp_allowed?
      return %w[サービス説明 比較表 使い分け FAQ エリア導線] if branded_search_page_needed?

      %w[結論 比較表 選び方 FAQ CTA]
    end

    def missing_elements
      explicit = Array(metadata["missing_elements"])
      return explicit if explicit.any? && serp_allowed?
      return [] unless serp_allowed?
      return %w[吸えログとは何か 競合サービスとの差分 喫煙店検索への導線 FAQ] if branded_search_page_needed?

      %w[比較 掲載件数 FAQ 内部リンク]
    end

    def reason
      if branded_search_page_needed?
        return "「#{source_query}」は指名検索ですが、SERP上位にBusiness領域外のページが多いため、SERP差分ではなく指名検索対策ページ不足として扱います。#{business&.name}とは何か、食べログ/Googleマップ/Rettyとの違い、大阪で喫煙できる店探しに特化していることを明示してください。"
      end

      metadata["revision_reason"].presence ||
        action_candidate.evaluation_reason.presence ||
        "比較という検索意図が強いため、比較表・掲載件数・FAQを追加して判断材料を増やしてください。"
    end

    def relevant_serp_results_from(results)
      return Array(results) if business.blank? || source_query.blank?

      relevance_filter.relevant_results(results)
    end

    def serp_relevance_scores
      @serp_relevance_scores ||= begin
        return [] unless serp_allowed?
        return [] if business.blank? || source_query.blank?

        relevance_filter.scored_results(raw_serp_results)
      end
    end

    def serp_relevance_summary
      total = serp_relevance_scores.size
      relevant = serp_relevance_scores.reject(&:excluded)
      excluded = serp_relevance_scores.select(&:excluded)
      status =
        if total.zero?
          "未取得"
        elsif branded_search_page_needed?
          "指名検索ページ不足"
        elsif relevant.size >= 3
          "関連SERPあり"
        elsif relevant.any?
          "関連SERP不足"
        else
          "Business領域外"
        end

      {
        status:,
        total_count: total,
        relevant_count: relevant.size,
        excluded_count: excluded.size,
        excluded_reasons: excluded.first(3).map { |row| "#{result_value(row.result, 'title').presence || 'title未取得'}: #{row.reason}" },
        guidance: serp_relevance_guidance(status)
      }
    end

    def branded_search_page_needed?
      return false unless serp_allowed?

      @branded_search_page_needed ||= relevance_filter.branded_query? &&
        raw_serp_results.any? &&
        serp_relevance_scores.reject(&:excluded).size < 3
    end

    def serp_allowed?
      @serp_allowed ||= begin
        context = metadata["candidate_kind"] == "new_business" ? :new_business_exploration : :existing_business_improvement
        Aicoo::DataSourcePolicy.for(business).enabled?(:serp, context:)
      end
    end

    def branded_search_gap
      <<~TEXT.strip
        「#{source_query}」は#{business&.name}を含む指名検索ですが、取得したSERPの多くがBusiness領域外です。
        SERP上位をそのまま根拠にせず、指名検索対策ページとして「#{business&.name}とは何か」「食べログ/Googleマップ/Rettyとの違い」「大阪で喫煙できる店探しに特化していること」を説明してください。
      TEXT
    end

    def relevance_filter
      @relevance_filter ||= Aicoo::Serp::ResultRelevance.new(business:, query: source_query)
    end

    def serp_relevance_guidance(status)
      case status
      when "指名検索ページ不足"
        "SERP差分ではなく、指名検索対策ページを作る"
      when "Business領域外"
        "無関係SERPを根拠にしない。ActionCandidate生成対象外にする"
      when "関連SERP不足"
        "関連SERPだけを根拠にし、不足分は候補ページ提示に留める"
      when "未取得"
        "SERP取得後に再具体化する"
      else
        "関連SERPのみを根拠に記事計画を生成する"
      end
    end

    def result_value(result, key)
      if result.respond_to?(:[])
        value = result[key]
        return value if value.present?

        symbol_key = key.to_sym
        return result[symbol_key] if result.respond_to?(:key?) && result.key?(symbol_key)
      end

      return result.public_send(key) if result.respond_to?(key)

      nil
    end

    def suelog_business?
      business&.name.to_s.include?("吸えログ")
    end

    def fallback_article_slug
      base = [
        business&.name,
        source_query.presence || action_candidate.title
      ].compact.join(" ")
      slug = base.parameterize
      slug.presence || "action-candidate-#{action_candidate.id}-article"
    end

    def explicit_file_changes
      Array(metadata["target_files"] || metadata["changed_files"]).compact_blank
    end

    def inferred_file_changes
      if new_article_creation?
        return %w[
          app/models/article.rb
          app/controllers/articles_controller.rb
          app/views/articles/show.html.erb
          app/services/article_seo_presenter.rb
        ]
      end

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
