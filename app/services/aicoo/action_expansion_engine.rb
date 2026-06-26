module Aicoo
  class ActionExpansionEngine
    ABSTRACT_TERMS = %w[
      順位改善 アクセス改善 記事改善 SEO改善 CV改善 導線改善 最適化 品質向上 改善する 強化する 伸ばす 見直す
    ].freeze
    LOW_CONFIDENCE = 35.to_d

    Result = Data.define(
      :expanded,
      :metadata,
      :execution_prompt,
      :practicality_bonus
    )

    def initialize(action_candidate)
      @action_candidate = action_candidate
    end

    def call
      return warning_result("Evidence不足のため、具体的な実行手順を作れません。") if evidence_insufficient?
      return warning_result("対象ページまたは対象KWが不足しているため、具体的な実行手順を作れません。") if target_unclear?

      expansion = build_expansion
      return expansion if expansion.expanded

      warning_result("対象ページ・対象KW・完了条件を特定できませんでした。")
    end

    private

    attr_reader :action_candidate

    def build_expansion
      case expansion_type
      when "ctr_title_rewrite"
        expanded_result(
          expansion_type: "ctr_title_rewrite",
          recommended_tasks: [ "SEOタイトル改訂", "meta description改訂", "冒頭文に主要KWを追加" ],
          execution_steps: [
            "対象ページ #{target_page_label} を開く",
            "対象KW #{target_keyword_label} の検索意図を確認する",
            "SEOタイトルに主要KWと具体的なエリア・用途を含める",
            "meta descriptionに喫煙情報・エリア情報・行動導線を入れる",
            "冒頭文に対象KWとユーザーの探している条件を追記する",
            "更新内容をActionResult登録用にメモする"
          ],
          completion_criteria: [
            "対象ページが特定されている",
            "対象KWが記録されている",
            "タイトルまたはmeta descriptionが改訂されている",
            "変更内容がActionResultに登録できる"
          ],
          expected_minutes: 35
        )
      when "serp_internal_link"
        expanded_result(
          expansion_type: "serp_internal_link",
          recommended_tasks: [ "内部リンク追加", "関連記事追加", "対象ページ強化" ],
          execution_steps: [
            "対象ページ #{target_page_label} を開く",
            "対象KW #{target_keyword_label} のSERP上位ページとの差分を確認する",
            "本文内に関連する近隣ページ・関連記事リンクを3〜5件追加する",
            "不足している比較情報・エリア情報を1ブロック追記する",
            "電話・地図・予約などの導線が見える位置にあるか確認する",
            "変更内容をActionResult登録用にメモする"
          ],
          completion_criteria: [
            "内部リンクが3件以上追加されている",
            "対象KWに対応する追記ブロックがある",
            "導線確認が完了している"
          ],
          expected_minutes: 45
        )
      when "store_page_flow"
        expanded_result(
          expansion_type: "store_page_flow",
          recommended_tasks: [ "近隣店舗リンク追加", "喫煙確認表示強化", "地図・電話導線改善" ],
          execution_steps: [
            "対象店舗ページ #{target_page_label} を開く",
            "対象KW #{target_keyword_label} と流入元を確認する",
            "喫煙可・エリア・店舗ジャンルが冒頭で分かるように追記する",
            "近隣の関連店舗リンクを3〜5件追加する",
            "電話・地図・予約導線を確認し、必要ならCTA文言を改善する",
            "変更内容をActionResult登録用にメモする"
          ],
          completion_criteria: [
            "店舗ページが特定されている",
            "近隣店舗リンクが3件以上追加されている",
            "電話・地図・予約導線を確認済み"
          ],
          expected_minutes: 40
        )
      when "content_area_expansion"
        expanded_result(
          expansion_type: "content_area_expansion",
          recommended_tasks: [ "エリア記事作成", "関連KW調査", "内部リンク設計" ],
          execution_steps: [
            "対象エリア #{target_area_label} と対象KW #{target_keyword_label} を確認する",
            "既存記事に同テーマがないか確認する",
            "検索意図に合わせた記事構成を作る",
            "記事1本を作成し、関連する既存ページへ内部リンクを追加する",
            "公開後、ActionResult登録用にURLと狙いKWをメモする"
          ],
          completion_criteria: [
            "対象エリアと対象KWが記録されている",
            "記事1本が作成または下書き化されている",
            "関連ページへの内部リンク方針がある"
          ],
          expected_minutes: 90
        )
      else
        nil
      end || warning_result("Evidenceから実行テンプレートを選べませんでした。")
    end

    def expanded_result(expansion_type:, recommended_tasks:, execution_steps:, completion_criteria:, expected_minutes:)
      metadata = base_metadata.merge(
        "expanded" => true,
        "expansion_type" => expansion_type,
        "target" => target_label,
        "target_url" => target_page,
        "target_keyword" => target_keyword,
        "target_area" => target_area,
        "target_pages" => [ target_page ].compact,
        "recommended_tasks" => recommended_tasks,
        "execution_steps" => execution_steps,
        "expected_minutes" => expected_minutes,
        "completion_criteria" => completion_criteria,
        "required_data_sources" => required_data_sources,
        "missing_data_sources" => [],
        "confidence" => confidence.to_s,
        "warning" => false,
        "warning_reason" => nil
      )

      Result.new(
        expanded: true,
        metadata:,
        execution_prompt: prompt_from(metadata),
        practicality_bonus: 12.to_d
      )
    end

    def warning_result(reason)
      metadata = base_metadata.merge(
        "expanded" => false,
        "expansion_type" => nil,
        "target" => target_label,
        "target_url" => target_page,
        "target_keyword" => target_keyword,
        "target_area" => target_area,
        "target_pages" => [ target_page ].compact,
        "recommended_tasks" => [],
        "execution_steps" => [],
        "expected_minutes" => nil,
        "completion_criteria" => [],
        "required_data_sources" => required_data_sources,
        "missing_data_sources" => missing_data_sources,
        "confidence" => confidence.to_s,
        "warning" => true,
        "warning_reason" => reason
      )
      Result.new(expanded: false, metadata:, execution_prompt: nil, practicality_bonus: 0.to_d)
    end

    def base_metadata
      {
        "original_title" => action_candidate.title,
        "original_reason" => action_candidate.evaluation_reason.presence || action_candidate.description,
        "abstract_candidate" => abstract_candidate?
      }
    end

    def expansion_type
      return "ctr_title_rewrite" if text.match?(/ctr|クリック|タイトル|meta|表示回数/) || metric_names.include?("impressions")
      return "serp_internal_link" if text.match?(/順位|serp|内部リンク|関連記事/) || evidence_sources.include?("serp")
      return "store_page_flow" if text.match?(/店舗|電話|地図|予約|喫煙|梅田|難波/)
      return "content_area_expansion" if text.match?(/記事|エリア|kw|キーワード|作成/)

      "store_page_flow" if playbook_prefers_seo?
    end

    def prompt_from(metadata)
      <<~PROMPT.strip
        実行手順:
        #{metadata.fetch("execution_steps").each_with_index.map { |step, index| "#{index + 1}. #{step}" }.join("\n")}

        完了条件:
        #{metadata.fetch("completion_criteria").map { |criterion| "- #{criterion}" }.join("\n")}
      PROMPT
    end

    def abstract_candidate?
      ABSTRACT_TERMS.any? { |term| text.include?(term.downcase) } ||
        target_page.blank? ||
        target_keyword.blank? ||
        action_candidate.execution_prompt.to_s.length < 40
    end

    def evidence_insufficient?
      evidence.blank? || evidence["warning"] == true || confidence < LOW_CONFIDENCE
    end

    def confidence
      @confidence ||= [ evidence["score"].to_d, evidence_items.sum { |item| item["confidence"].to_d } / [ evidence_items.size, 1 ].max ].max
    end

    def target_label
      target_page.presence || target_keyword.presence || target_area.presence || action_candidate.title
    end

    def target_page_label
      target_page.presence || "対象ページ"
    end

    def target_keyword_label
      target_keyword.presence || "対象KW"
    end

    def target_area_label
      target_area.presence || "対象エリア"
    end

    def target_page
      @target_page ||= evidence_items.filter_map { |item| item["page"].presence || item["url"].presence }.first ||
        text[/\/[a-z0-9_\-\/]+/]
    end

    def target_keyword
      @target_keyword ||= evidence_items.filter_map { |item| item["keyword"].presence }.first ||
        text[/「([^」]+)」/, 1]
    end

    def target_area
      @target_area ||= text[/梅田|難波|心斎橋|中崎町|東京|大阪|京都|神戸/]
    end

    def required_data_sources
      (evidence_sources.presence || [ "evidence" ]).uniq
    end

    def missing_data_sources
      return [] unless evidence_insufficient?

      Array(evidence["missing_sources"]).presence || [ "gsc", "ga4", "serp" ]
    end

    def target_unclear?
      target_page.blank? && target_keyword.blank? && !text.match?(/梅田|難波|心斎橋|中崎町|店舗|[0-9]+件|[0-9]+本/)
    end

    def playbook_prefers_seo?
      playbook = action_candidate.metadata.to_h["business_playbook"].to_h
      row_type = playbook.dig("row", "type").to_s
      row_type.match?(/seo|serp|content/)
    end

    def metric_names
      evidence_items.filter_map { |item| item["metric_name"].presence }
    end

    def evidence_sources
      evidence_items.filter_map { |item| item["source"].presence }
    end

    def evidence
      @evidence ||= action_candidate.metadata.to_h["evidence"].to_h
    end

    def evidence_items
      @evidence_items ||= Array(evidence["items"])
    end

    def text
      @text ||= [
        action_candidate.title,
        action_candidate.description,
        action_candidate.execution_prompt,
        action_candidate.evaluation_reason,
        evidence_items.map { |item| [ item["title"], item["summary"], item["page"], item["keyword"] ] }
      ].flatten.compact.join(" ").downcase
    end
  end
end
