module Aicoo
  class ActionCandidateEvidencePresenter
    SOURCE_LABELS = {
      "gsc" => "GSC",
      "ga4" => "GA4",
      "business_db" => "Business DB",
      "serp" => "SERP",
      "activity_log" => "Activity Log"
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

    def source_label
      sources = Array(evidence["source"]).compact_blank
      return "未特定" if sources.empty?

      sources.map { |source| SOURCE_LABELS.fetch(source.to_s, source.to_s) }.join(" / ")
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
      evidence["reason"].presence || "根拠データは保存されていますが、理由文は未設定です。"
    end

    def lines
      [
        "根拠: #{source_label}",
        "対象: #{target_label}",
        "現在: #{current_label}",
        "目標: #{benchmark_label}",
        "実施量: #{amount_label}",
        "期待効果: #{expected_effect_label}"
      ]
    end

    def table_rows
      [
        [ "根拠データ", source_label ],
        [ "課題タイプ", evidence["issue_type"].presence || "-" ],
        [ "対象", target_label ],
        [ "現在値", current_label ],
        [ "目標値", benchmark_label ],
        [ "実施量", amount_label ],
        [ "期待効果", expected_effect_label ],
        [ "理由", reason ]
      ]
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
