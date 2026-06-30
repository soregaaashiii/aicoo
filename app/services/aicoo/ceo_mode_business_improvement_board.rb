module Aicoo
  class CeoModeBusinessImprovementBoard
    include Rails.application.routes.url_helpers

    MAX_SOURCE_RECORDS = 80
    MAX_BUSINESS_CARDS = 24
    DEFAULT_SUCCESS_PROBABILITY = 0.35

    Board = Data.define(:improvements, :business_cards, :today_one, :critical_business_blockers)
    Improvement = Data.define(
      :key,
      :rank,
      :business,
      :title,
      :category,
      :expected_profit_yen,
      :success_probability,
      :required_minutes,
      :expected_hourly_value_yen,
      :learning_value_yen,
      :roi,
      :source_label,
      :reason_lines,
      :detail_path,
      :codex_path,
      :codex_method,
      :defer_path
    )
    BusinessCard = Data.define(
      :business,
      :expected_profit_yen,
      :attention_score,
      :roi,
      :state_label,
      :recommended_count,
      :action_candidate_count,
      :auto_revision_task_count,
      :last_improved_at,
      :detail_path,
      :improvements_path
    )
    CriticalBusinessBlocker = Data.define(:business, :title, :message, :path)

    def initialize(deferred_task_keys: [])
      @deferred_task_keys = Array(deferred_task_keys).compact_blank
    end

    def call
      ranked = ranked_improvements
      Board.new(
        improvements: ranked.first(10),
        business_cards: business_cards(ranked),
        today_one: ranked.first,
        critical_business_blockers: critical_business_blockers
      )
    end

    private

    attr_reader :deferred_task_keys

    def ranked_improvements
      rows = action_candidate_improvements + auto_revision_task_improvements
      rows = rows.reject { |row| deferred_task_keys.include?(row.key) }
      rows = rows.uniq { |row| [ row.business&.id, row.title ] }
      rows = rows.sort_by { |row| ranking_key(row) }
      rows.map.with_index(1) { |row, index| row.with(rank: index) }
    end

    def action_candidate_improvements
      ActionCandidate.includes(:business, :auto_revision_tasks)
                     .active_for_ranking
                     .where.not(business_id: nil)
                     .where.not(action_type: "data_preparation")
                     .order(Arel.sql("final_score DESC NULLS LAST, expected_profit_yen DESC NULLS LAST"))
                     .limit(MAX_SOURCE_RECORDS)
                     .filter_map do |candidate|
        next if candidate.business&.system_business?

        build_candidate_improvement(candidate)
      end
    end

    def auto_revision_task_improvements
      AutoRevisionTask.includes(:business, :action_candidate)
                      .active
                      .by_priority
                      .limit(MAX_SOURCE_RECORDS)
                      .filter_map do |task|
        next if task.business&.system_business?

        build_auto_revision_improvement(task)
      end
    end

    def build_candidate_improvement(candidate)
      title = human_title(candidate.title)
      category = category_for(candidate.action_type, candidate.title)
      expected_profit = candidate.expected_profit_yen.to_i
      success_probability = candidate.success_probability.presence || DEFAULT_SUCCESS_PROBABILITY
      required_minutes = minutes_for(candidate.expected_hours)
      learning_value = candidate.expected_learning_value_yen.to_i
      auto_revision_task = candidate.auto_revision_tasks.active.by_priority.first

      Improvement.new(
        key: "action_candidate:#{candidate.id}",
        rank: nil,
        business: candidate.business,
        title:,
        category:,
        expected_profit_yen: expected_profit,
        success_probability:,
        required_minutes:,
        expected_hourly_value_yen: candidate.expected_hourly_value_yen.to_i,
        learning_value_yen: learning_value,
        roi: candidate.roi,
        source_label: source_label(candidate.generation_source),
        reason_lines: reason_lines_for_candidate(candidate, category:),
        detail_path: action_candidate_path(candidate),
        codex_path: auto_revision_task ? export_codex_prompt_auto_revision_task_path(auto_revision_task) : generate_codex_prompt_draft_action_candidate_path(candidate),
        codex_method: auto_revision_task ? :get : :post,
        defer_path: defer_owner_focus_path(task_key: "action_candidate:#{candidate.id}")
      )
    end

    def build_auto_revision_improvement(task)
      candidate = task.action_candidate
      expected_profit = candidate&.expected_profit_yen.to_i
      required_minutes = minutes_for(candidate&.expected_hours)
      success_probability = candidate&.success_probability.presence || probability_for_risk(task.risk_level)
      category = category_for(task.metadata.to_h["action_type"] || candidate&.action_type, task.title)

      Improvement.new(
        key: "auto_revision_task:#{task.id}",
        rank: nil,
        business: task.business,
        title: human_title(task.title),
        category:,
        expected_profit_yen: expected_profit,
        success_probability:,
        required_minutes:,
        expected_hourly_value_yen: hourly_value(expected_profit, required_minutes),
        learning_value_yen: candidate&.expected_learning_value_yen.to_i,
        roi: candidate&.roi,
        source_label: "Codex改修候補",
        reason_lines: reason_lines_for_auto_revision(task, candidate:, category:),
        detail_path: auto_revision_task_path(task),
        codex_path: export_codex_prompt_auto_revision_task_path(task),
        codex_method: :get,
        defer_path: defer_owner_focus_path(task_key: "auto_revision_task:#{task.id}")
      )
    end

    def business_cards(improvements)
      businesses = Business.real_businesses.order(:name).limit(MAX_BUSINESS_CARDS).to_a
      business_ids = businesses.map(&:id)
      action_counts = ActionCandidate.active_for_ranking.where(business_id: business_ids).group(:business_id).count
      auto_revision_counts = AutoRevisionTask.active.where(business_id: business_ids).group(:business_id).count
      expected_profit_by_business = improvements.group_by { |row| row.business&.id }
                                                .transform_values { |rows| rows.sum(&:expected_profit_yen) }
      recommended_count_by_business = improvements.group_by { |row| row.business&.id }
                                                   .transform_values(&:size)
      last_improved_at_by_business = ActionResult.where(business_id: business_ids)
                                                 .group(:business_id)
                                                 .maximum(:created_at)

      businesses.map do |business|
        expected_profit = expected_profit_by_business.fetch(business.id, 0)
        recommended_count = recommended_count_by_business.fetch(business.id, 0)
        action_count = action_counts.fetch(business.id, 0)
        auto_revision_count = auto_revision_counts.fetch(business.id, 0)

        BusinessCard.new(
          business:,
          expected_profit_yen: expected_profit,
          attention_score: attention_score_for(business, action_count:, auto_revision_count:),
          roi: business_roi(expected_profit:, action_count:, auto_revision_count:),
          state_label: business_state_label(business),
          recommended_count:,
          action_candidate_count: action_count,
          auto_revision_task_count: auto_revision_count,
          last_improved_at: last_improved_at_by_business[business.id],
          detail_path: business_path(business),
          improvements_path: business_path(business, anchor: "ai-improvement-proposals")
        )
      end.sort_by { |row| [ -row.expected_profit_yen, -row.attention_score, row.business.name ] }
    end

    def critical_business_blockers
      Aicoo::BusinessIntegrationHealth.new.call.critical_businesses.filter_map do |row|
        business = row.business
        next if business.system_business?

        CriticalBusinessBlocker.new(
          business:,
          title: "#{business.name} の分析が止まっています",
          message: row.warnings.first || "重大な連携エラーがあります。",
          path: business_path(business, anchor: "connection-status")
        )
      end.first(3)
    rescue StandardError => e
      Rails.logger.warn("[CEO MODE] critical blocker summary skipped: #{e.class}: #{e.message}")
      []
    end

    def ranking_key(row)
      [
        -row.expected_profit_yen.to_i,
        -(row.roi || 0).to_d,
        -row.success_probability.to_d,
        row.required_minutes.to_i.zero? ? 999_999 : row.required_minutes.to_i,
        -row.learning_value_yen.to_i,
        row.business&.name.to_s,
        row.title.to_s
      ]
    end

    def reason_lines_for_candidate(candidate, category:)
      lines = []
      lines << "期待利益が#{yen(candidate.expected_profit_yen)}見込めます。" if candidate.expected_profit_yen.to_i.positive?
      lines << "成功率は#{percentage(candidate.success_probability)}です。" if candidate.success_probability.to_d.positive?
      lines << "#{category}改善として、今日の利益増加に直結しやすい候補です。"
      lines << "学習価値が#{yen(candidate.expected_learning_value_yen)}あり、今後の提案精度も上がります。" if candidate.expected_learning_value_yen.to_i.positive?
      lines << clean_reason(candidate.evaluation_reason) if candidate.evaluation_reason.present?
      lines.compact_blank.first(4)
    end

    def reason_lines_for_auto_revision(task, candidate:, category:)
      lines = []
      lines << "#{category}改善をCodexへ渡せる実行単位まで整理済みです。"
      lines << "リスクは#{risk_label(task.risk_level)}です。"
      lines << "期待利益は#{yen(candidate.expected_profit_yen)}です。" if candidate&.expected_profit_yen.to_i.positive?
      lines << clean_reason(task.execution_prompt) if task.execution_prompt.present?
      lines.compact_blank.first(4)
    end

    def category_for(action_type, title)
      text = [ action_type, title ].join(" ").downcase
      return "SEO" if text.match?(/seo|serp|順位|検索|title|meta/)
      return "LP" if text.match?(/lp|landing|cta|form/)
      return "価格" if text.match?(/price|pricing|価格|課金/)
      return "広告" if text.match?(/ads|ad|広告/)
      return "UI" if text.match?(/ui|ux|導線|画面|フォーム/)
      return "記事" if text.match?(/article|記事|コンテンツ/)
      return "収益" if text.match?(/revenue|cv|conversion|売上|収益|予約|電話|地図/)
      return "内部リンク" if text.match?(/internal_link|内部リンク/)
      return "AI改善" if text.match?(/automation|ai|codex|自動/)
      return "Learning" if text.match?(/learning|学習/)
      return "Calibration" if text.match?(/calibration|補正|評価/)

      "収益"
    end

    def human_title(title)
      title.to_s.gsub(/ActionCandidate|AutoRevisionTask|metadata|Generation Source/i, "").squish.presence || "事業改善を実行する"
    end

    def clean_reason(text)
      text.to_s.gsub(/ActionCandidate|metadata|Generation Source/i, "").squish.truncate(110)
    end

    def source_label(source)
      {
        "manual" => "手動入力",
        "seed" => "初期候補",
        "ai_business" => "AI事業分析",
        "ai_cross_business" => "AI横断分析",
        "ai_reevaluation" => "AI再評価",
        "ai_insight" => "AI Insight",
        "learning_report" => "Learning",
        "opportunity_discovery" => "Opportunity"
      }.fetch(source.to_s, source.to_s.presence || "改善候補")
    end

    def business_state_label(business)
      [ business.lifecycle_stage, business.resource_status ].compact_blank.join(" / ")
    end

    def attention_score_for(_business, action_count:, auto_revision_count:)
      [ (action_count * 8) + (auto_revision_count * 12), 100 ].min
    end

    def business_roi(expected_profit:, action_count:, auto_revision_count:)
      denominator = [ action_count + auto_revision_count, 1 ].max
      expected_profit.to_d / denominator
    end

    def minutes_for(hours)
      return 0 if hours.blank?

      (hours.to_d * 60).round
    end

    def hourly_value(expected_profit, minutes)
      return 0 if minutes.to_i.zero?

      (expected_profit.to_d / (minutes.to_d / 60)).round
    end

    def probability_for_risk(risk_level)
      case risk_level
      when "low" then 0.75
      when "medium" then 0.55
      else 0.35
      end
    end

    def risk_label(risk_level)
      { "low" => "低", "medium" => "中", "high" => "高" }.fetch(risk_level.to_s, risk_level.to_s)
    end

    def yen(value)
      "#{value.to_i.to_fs(:delimited)}円"
    end

    def percentage(value)
      "#{(value.to_d * 100).round}%"
    end
  end
end
