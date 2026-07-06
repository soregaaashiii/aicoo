module Aicoo
  class ActionCandidateEvidencePresenter
    SOURCE_LABELS = {
      "gsc" => "GSC",
      "ga4" => "GA4",
      "business_db" => "Business DB",
      "internal" => "Internal",
      "serp" => "SERP",
      "x" => "X",
      "reddit" => "Reddit",
      "news" => "News",
      "activity_log" => "Activity Log"
    }.freeze
    SEO_ACTION_TYPE_LABELS = {
      "add_listings" => "掲載店舗追加",
      "verify_listings" => "確認済み追加",
      "create_area_article" => "エリア記事作成",
      "create_genre_article" => "ジャンル記事作成",
      "rewrite_existing_article" => "既存記事リライト",
      "add_shop_links" => "店舗リンク追加",
      "improve_shop_page" => "店舗ページ改善",
      "improve_ctr_title" => "CTRタイトル改善",
      "respond_to_serp_gap" => "SERP差分対応",
      "improve_cv_path" => "CV導線改善"
    }.freeze
    EXECUTION_MODE_LABELS = {
      "code_revision" => "Codex改修",
      "manual_operation" => "手作業",
      "content_creation" => "記事作成",
      "data_operation" => "データ作業"
    }.freeze

    def initialize(action_candidate)
      @action_candidate = action_candidate
    end

    def analyzer_evidence?
      evidence["issue_type"].present? || evidence["target_amount"].present?
    end

    def concrete?
      [
        evidence["target_amount"],
        evidence["query"],
        evidence["page_path"],
        evidence["area"],
        evidence["genre"],
        evidence["metric_before"],
        evidence["benchmark_value"],
        evidence["current_value"]
      ].any?(&:present?)
    end

    def seo_action_type
      action_candidate.metadata.to_h["seo_action_type"].presence
    end

    def seo_action_type?
      seo_action_type.present?
    end

    def seo_action_type_label
      SEO_ACTION_TYPE_LABELS.fetch(seo_action_type.to_s, seo_action_type.to_s)
    end

    def execution_units
      source = Array(action_plan["execution_units"]).presence || Array(action_candidate.metadata.to_h["execution_units"])
      source.map do |unit|
        unit.to_h.deep_stringify_keys
      end
    end

    def execution_units?
      execution_units.any?
    end

    def execution_unit_lines(limit: 3)
      execution_units.first(limit).map.with_index(1) do |unit, index|
        "#{index}. #{unit['label']}（#{unit['estimated_minutes'].presence || '-'}分）"
      end
    end

    def execution_units_warning?
      false
    end

    def execution_mode
      action_plan["execution_mode"].presence || action_candidate.execution_mode
    end

    def execution_mode_label
      EXECUTION_MODE_LABELS.fetch(execution_mode.to_s, execution_mode.to_s.presence || "Codex改修")
    end

    def source_label
      sources = data_sources_used.presence || Array(evidence["source"]).compact_blank
      return "未特定" if sources.empty?

      sources.map { |source| SOURCE_LABELS.fetch(source.to_s, source.to_s) }.join(" / ")
    end

    def data_sources_used
      Array(action_candidate.metadata.to_h["data_sources_used"]).compact_blank
    end

    def target_label
      [
        evidence["query"].presence && "「#{evidence['query']}」",
        evidence["page_path"],
        evidence["area"].presence && "#{evidence['area']}エリア",
        evidence["genre"]
      ].compact_blank.join(" / ").presence || "未特定"
    end

    def current_label
      metric_label(evidence["current_value"].presence || evidence["metric_before"])
    end

    def benchmark_label
      metric_label(evidence["benchmark_value"])
    end

    def amount_label
      return "未設定" if evidence["target_amount"].blank?

      "#{evidence['target_amount']}#{evidence['target_unit']}"
    end

    def expected_effect_label
      evidence["expected_effect"].presence || action_candidate.evaluation_reason.to_s.lines.grep(/期待効果/).first.to_s.sub("期待効果:", "").strip.presence || "未算出"
    end

    def reason
      action_plan["goal"].presence || evidence["reason"].presence || "根拠データに基づいて生成された作業です。"
    end

    def action_plan
      @action_plan ||= action_candidate.metadata.to_h.fetch("action_plan", {}).to_h.deep_stringify_keys
    end

    def action_plan?
      action_plan["summary"].present?
    end

    def summary
      action_plan["summary"].presence ||
        action_candidate.metadata.to_h["concrete_task"].presence ||
        action_candidate.metadata.to_h.dig("decision", "selected", "concrete_task").presence
    end

    def owner_output
      action_plan["owner_output"].presence
    end

    def execution_steps
      Array(action_plan["execution_steps"]).compact_blank
    end

    def lines
      [
        owner_output.present? ? owner_output.lines.first(2).join(" ").squish : nil,
        "実行方法: #{execution_mode_label}",
        execution_units? ? "今日やる単位: #{execution_units.size}件" : nil,
        "根拠: #{source_label}",
        "対象: #{target_label}",
        "現在: #{current_label}",
        "目標: #{benchmark_label}",
        "実施量: #{amount_label}",
        "期待効果: #{expected_effect_label}"
      ].compact
    end

    def table_rows
      [
        seo_action_type? ? [ "作業カテゴリ", seo_action_type_label ] : nil,
        [ "実行方法", execution_mode_label ],
        execution_units? ? [ "今日やる単位", execution_unit_lines(limit: 5).join(" / ") ] : nil,
        [ "根拠データ", source_label ],
        [ "課題タイプ", evidence["issue_type"].presence || "-" ],
        [ "対象", target_label ],
        [ "現在値", current_label ],
        [ "目標値", benchmark_label ],
        [ "実施量", amount_label ],
        [ "期待効果", expected_effect_label ],
        [ "理由", reason ]
      ].compact
    end

    private

    attr_reader :action_candidate

    def evidence
      @evidence ||= action_candidate.metadata.to_h.fetch("evidence", {}).to_h
    end

    def metric_label(value)
      return "未設定" if value.blank?

      numeric = BigDecimal(value.to_s)
      return "#{(numeric * 100).round(1)}%" if numeric >= 0 && numeric <= 1

      numeric.frac.zero? ? numeric.to_i.to_s : numeric.round(2).to_s
    rescue ArgumentError
      value.to_s
    end
  end
end
