module Aicoo
  class CeoSummaryBuilder
    INTERNAL_TERMS = [
      "Opportunity",
      "Generation Source",
      "metadata",
      "Internal Score",
      "Builder"
    ].freeze
    CEO_REPLACEMENTS = {
      "Analytics Import" => "データ取り込み",
      "ActionCandidate" => "実行候補",
      "ActionResult" => "結果登録",
      "Explore Daily Routine" => "外部シグナル確認",
      "Explore Import" => "外部シグナル取り込み",
      "Codex Prompt" => "Codex用依頼文",
      "Daily Run" => "自動巡回"
    }.freeze

    TASK_MINUTES = {
      /タイトル|meta|冒頭文/ => 5,
      /内部リンク|関連記事|近隣/ => 10,
      /確認済み|店舗|電話|地図|予約|CTA|導線/ => 15,
      /記事|LP|構成|作成/ => 60
    }.freeze

    Summary = Data.define(
      :title,
      :reason_lines,
      :work_lines,
      :target_label,
      :time_lines,
      :total_minutes,
      :expected_profit_yen,
      :roi,
      :success_probability,
      :completion_criteria,
      :start_label,
      :codex_label,
      :empty?
    )

    def self.human_label(text)
      label = text.to_s.dup
      CEO_REPLACEMENTS.each { |internal, replacement| label.gsub!(internal, replacement) }
      INTERNAL_TERMS.each { |term| label.gsub!(term, "") }
      label.gsub(/\s+/, " ").strip.presence || "処理する"
    end

    def initialize(task: nil, action_candidate: nil, opportunity: nil)
      @task = task
      @action_candidate = action_candidate
      @opportunity = opportunity
    end

    def call
      if candidate
        candidate_summary
      elsif opportunity
        opportunity_summary
      elsif task
        task_summary
      else
        empty_summary
      end
    end

    private

    attr_reader :task, :action_candidate, :opportunity

    def candidate
      @candidate ||= action_candidate || candidate_from_task
    end

    def candidate_summary
      expansion = candidate.metadata.to_h["action_expansion"].to_h
      tasks = Array(expansion["recommended_tasks"])
      criteria = Array(expansion["completion_criteria"])
      total_minutes = expansion["expected_minutes"].presence || task_minutes(tasks).values.sum

      Summary.new(
        title: clean_title(candidate_title(expansion, tasks)),
        reason_lines: evidence_lines(candidate.metadata.to_h["evidence"].to_h),
        work_lines: work_lines_for(expansion, tasks),
        target_label: target_label_for(expansion),
        time_lines: time_lines_for(tasks, total_minutes),
        total_minutes: total_minutes.to_i,
        expected_profit_yen: candidate.expected_profit_yen.to_i,
        roi: candidate.roi,
        success_probability: candidate.success_probability,
        completion_criteria: criteria.presence || [ "変更内容を記録する", "結果登録へ進める状態にする" ],
        start_label: "実行を開始する",
        codex_label: "Codex用の依頼文を作る",
        empty?: false
      )
    end

    def opportunity_summary
      Summary.new(
        title: clean_title("#{opportunity.title}を小さく検証する"),
        reason_lines: [
          opportunity.summary.presence || opportunity.description.presence || "外部シグナルから事業機会として検出されています。",
          "期待値 #{format_yen(opportunity.expected_value_yen)} / 信頼度 #{opportunity.confidence.to_i}"
        ],
        work_lines: [ "仮説を確認する", "実行候補へ変換できるか判断する", "低コストで検証できる形に分解する" ],
        target_label: opportunity.business&.name || "新規検証テーマ",
        time_lines: [ "確認 5分", "候補化 5分" ],
        total_minutes: 10,
        expected_profit_yen: opportunity.expected_value_yen.to_i,
        roi: nil,
        success_probability: opportunity.confidence.to_d / 100,
        completion_criteria: [ "承認・却下・実行候補化のどれかを選ぶ" ],
        start_label: "実行候補にする",
        codex_label: nil,
        empty?: false
      )
    end

    def task_summary
      Summary.new(
        title: clean_title(task.title.to_s),
        reason_lines: [ clean_title(task.reason.to_s.presence || task.description.to_s) ],
        work_lines: [ "詳細を開いて、必要な処理を完了する" ],
        target_label: task.target_label,
        time_lines: [ "確認 5分" ],
        total_minutes: 5,
        expected_profit_yen: nil,
        roi: nil,
        success_probability: nil,
        completion_criteria: [ "表示された処理を完了する" ],
        start_label: "処理を進める",
        codex_label: nil,
        empty?: false
      )
    end

    def empty_summary
      Summary.new(
        title: "今すぐ処理すべき作業はありません",
        reason_lines: [ "実行待ち・結果登録・承認待ち・重大な異常はありません。" ],
        work_lines: [],
        target_label: nil,
        time_lines: [],
        total_minutes: 0,
        expected_profit_yen: nil,
        roi: nil,
        success_probability: nil,
        completion_criteria: [],
        start_label: nil,
        codex_label: nil,
        empty?: true
      )
    end

    def candidate_from_task
      return unless task

      if task.target_path.to_s.match?(%r{/action_candidates/\d+})
        ActionCandidate.find_by(id: task.target_path.to_s.split("/").last)
      elsif task.target_path.to_s.match?(%r{/action_executions/\d+})
        ActionExecution.find_by(id: task.target_path.to_s.split("/").last)&.action_candidate
      end
    end

    def candidate_title(expansion, tasks)
      task_name = tasks.first.presence || candidate.title
      target = target_label_for(expansion)

      if expansion["expanded"] && tasks.any? && target.present? && target != candidate.title
        "#{target}で#{task_name}を行う"
      elsif task_name == candidate.title
        business_specific_title(candidate.title)
      else
        "#{task_name}を行う"
      end
    end

    def business_specific_title(title)
      return title.gsub(/順位改善|アクセス改善|記事改善|SEO改善|CV改善|導線改善|最適化|品質向上/, "改善") unless candidate.business
      return "確認済み店舗を増やす" if store_media_business? && title.match?(/店舗|確認/)
      return "検索流入が伸びるページを改善する" if store_media_business?
      return "オンボーディングを改善する" if candidate.business.description.to_s.match?(/saas|アプリ|app/i)

      title
    end

    def work_lines_for(expansion, tasks)
      lines = []
      lines << "対象: #{target_label_for(expansion)}" if target_label_for(expansion).present?
      lines << "狙うKW: #{expansion['target_keyword']}" if expansion["target_keyword"].present?
      lines += tasks.first(4).map { |task_name| "作業: #{task_name}" }
      lines.presence || [ "詳細画面の実行ガイドに沿って進める" ]
    end

    def evidence_lines(evidence)
      summary = Array(evidence["summary"]).map { |line| line.to_s.sub(/\A・/, "") }.first(4)
      return summary if summary.any?

      items = Array(evidence["items"]).first(3).filter_map do |item|
        metric = item["metric_name"].presence || item["title"].presence
        current = item["current_value"].presence
        change = item["change_rate"].presence
        next unless metric

        [ metric, current && "現在 #{current}", change && "変化 #{change}" ].compact.join(" / ")
      end
      items.presence || [ "根拠データが不足しています。詳細画面でEvidenceを確認してください。" ]
    end

    def target_label_for(expansion)
      expansion["target"].presence ||
        expansion["target_url"].presence ||
        expansion["target_keyword"].presence ||
        candidate&.business&.name
    end

    def time_lines_for(tasks, total_minutes)
      minutes = task_minutes(tasks)
      return [ "合計 #{total_minutes.to_i}分" ] if minutes.empty?

      minutes.map { |task_name, minute| "#{task_name} #{minute}分" } + [ "合計 #{total_minutes.to_i}分" ]
    end

    def task_minutes(tasks)
      tasks.first(5).to_h do |task_name|
        minute = TASK_MINUTES.find { |pattern, _| task_name.match?(pattern) }&.last || 10
        [ task_name, minute ]
      end
    end

    def clean_title(text)
      self.class.human_label(text).presence || "今日やる作業"
    end

    def format_yen(value)
      "#{value.to_i.to_fs(:delimited)}円"
    end

    def store_media_business?
      candidate.business.name.to_s.include?("吸えログ") ||
        candidate.business.description.to_s.match?(/smoking|seo media|店舗|メディア/i)
    end
  end
end
