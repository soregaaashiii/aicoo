module Aicoo
  class PracticalityScorer
    MIN_CANDIDATE_SCORE = 30.to_d
    SCORE_KEYS = %i[
      target_clarity_score
      action_clarity_score
      deliverable_score
      execution_ready_score
      dependency_score
      automation_score
    ].freeze

    Result = Data.define(
      :practicality_score,
      :practicality_warning,
      :practicality_reason,
      :subscores,
      :missing_items,
      :metadata
    )

    def initialize(subject)
      @subject = subject
    end

    def call
      subscores = {
        target_clarity_score: target_clarity_score,
        action_clarity_score: action_clarity_score,
        deliverable_score: deliverable_score,
        execution_ready_score: execution_ready_score,
        dependency_score: dependency_score,
        automation_score: automation_score
      }
      score = weighted_score(subscores)
      score = apply_evidence_penalty(score)
      missing_items = missing_items_for(subscores)
      missing_items << "根拠データが不足しています" if evidence_insufficient?
      warning = score < MIN_CANDIDATE_SCORE || missing_items.any?

      Result.new(
        practicality_score: score,
        practicality_warning: warning,
        practicality_reason: reason_for(score, missing_items),
        subscores:,
        missing_items:,
        metadata: {
          "practicality_score" => score.to_s,
          "subscores" => subscores.transform_values(&:to_s),
          "missing_items" => missing_items,
          "warning" => warning,
          "reason" => reason_for(score, missing_items)
        }
      )
    end

    private

    attr_reader :subject

    def text
      @text ||= [
        value_for(:title),
        value_for(:description),
        value_for(:summary),
        value_for(:execution_prompt),
        value_for(:evaluation_reason),
        action_expansion_text
      ].compact.join(" ").downcase
    end

    def target_clarity_score
      score = 35
      score += 30 if text.match?(/梅田|難波|心斎橋|長崎橋|エリア|記事|店舗|ページ|lp|url|ctr|pv|表示回数|クリック|上位\d+|[0-9]+件|[0-9]+本/)
      score += 20 if subject.respond_to?(:business) && subject.business.present?
      score -= 50 if vague_target?
      clamp(score)
    end

    def action_clarity_score
      score = 30
      score += 35 if text.match?(/タイトル変更|タイトル改訂|内部リンク|cta|追加|確認|作成|公開|登録|リライト|比較記事|近隣店舗リンク|lp|テスト|調査/)
      score += 15 if value_for(:action_type).present? && value_for(:action_type) != "other"
      score -= 50 if vague_action?
      clamp(score)
    end

    def deliverable_score
      score = 30
      score += 35 if text.match?(/[0-9]+件|[0-9]+本|[0-9]+記事|lp1|lp 1|1枚|リスト|レポート|確認済み|公開/)
      score += 15 if value_for(:expected_hours).present?
      score -= 20 if text.match?(/分析する|検討する|整理する/) && !text.match?(/レポート|リスト|[0-9]+/)
      score -= 20 if vague_target? || vague_action?
      clamp(score)
    end

    def execution_ready_score
      score = 35
      score += 25 if value_for(:execution_prompt).present?
      score += 20 if text.match?(/今日|すぐ|小さく|最小|完了条件|実行内容/)
      score += 10 if value_for(:expected_hours).to_d.positive? && value_for(:expected_hours).to_d <= 4
      score -= 30 if text.match?(/要調整|未定|不明|あとで|将来/)
      score -= 20 if vague_target? || vague_action?
      clamp(score)
    end

    def dependency_score
      score = 80
      score -= 45 if text.match?(/api待ち|外部待ち|人待ち|承認待ち|データ待ち|未接続|credential|oauth|ga4未設定|gsc未設定/)
      score -= 25 if text.match?(/調査後|確認後|依頼後/)
      clamp(score)
    end

    def automation_score
      score = 35
      score += 30 if text.match?(/codex|自動|生成|一括|バッチ|スクリプト|csv|json|テンプレート/)
      score += 15 if value_for(:action_type).in?(%w[seo_article seo_improvement build_lp data_preparation automation])
      clamp(score)
    end

    def weighted_score(subscores)
      (
        subscores.fetch(:target_clarity_score) * 0.2 +
        subscores.fetch(:action_clarity_score) * 0.22 +
        subscores.fetch(:deliverable_score) * 0.18 +
        subscores.fetch(:execution_ready_score) * 0.18 +
        subscores.fetch(:dependency_score) * 0.12 +
        subscores.fetch(:automation_score) * 0.1
      ).round(2)
    end

    def apply_evidence_penalty(score)
      return score unless evidence_insufficient?

      [ score.to_d - 8, 0.to_d ].max.round(2)
    end

    def missing_items_for(subscores)
      items = []
      items << "対象が特定されていません" if subscores.fetch(:target_clarity_score) < 45
      items << "やる内容が抽象的です" if subscores.fetch(:action_clarity_score) < 45
      items << "成果物が不明確です" if subscores.fetch(:deliverable_score) < 45
      items << "今日すぐ着手する情報が不足しています" if subscores.fetch(:execution_ready_score) < 45
      items << "外部待ち・依存関係があります" if subscores.fetch(:dependency_score) < 50
      items
    end

    def reason_for(score, missing_items)
      return "今日すぐ実行できる具体度です。" if score >= 70 && missing_items.empty?
      return "実行可能性は中程度です。#{missing_items.first}" if score >= MIN_CANDIDATE_SCORE

      "ActionCandidate化には具体化が必要です。#{missing_items.first || '対象・成果物・実行手順を明確にしてください。'}"
    end

    def vague_target?
      text.match?(/アクセスが増えているページ|よく見られている|対象を探す|どこか|全体|改善余地/)
    end

    def vague_action?
      text.match?(/改善する|最適化する|品質向上|強化する|伸ばす|見直す/) &&
        !text.match?(/タイトル|内部リンク|cta|記事|店舗|lp|確認|追加|変更|作成/)
    end

    def value_for(attribute)
      return subject.public_send(attribute) if subject.respond_to?(attribute)
      return subject.metadata.to_h[attribute.to_s] if subject.respond_to?(:metadata)

      nil
    end

    def action_expansion_text
      return unless subject.respond_to?(:metadata)

      expansion = subject.metadata.to_h["action_expansion"].to_h
      [
        expansion["target"],
        expansion["target_url"],
        expansion["target_keyword"],
        expansion["target_area"],
        expansion["recommended_tasks"],
        expansion["execution_steps"],
        expansion["completion_criteria"]
      ].flatten.compact.join(" ")
    end

    def evidence_insufficient?
      return false unless subject.respond_to?(:metadata)

      evidence = subject.metadata.to_h["evidence"].to_h
      evidence.blank? || evidence["warning"] == true || evidence["score"].to_d < Aicoo::EvidenceBuilder::INSUFFICIENT_SCORE
    end

    def clamp(value)
      [ [ value.to_d, 0.to_d ].max, 100.to_d ].min
    end
  end
end
