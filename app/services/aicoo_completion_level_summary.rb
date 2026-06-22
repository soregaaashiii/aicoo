class AicooCompletionLevelSummary
  NextAction = Data.define(:label, :path, :reason) do
    def available?
      path.present?
    end
  end

  Level = Data.define(
    :level,
    :title,
    :status,
    :description,
    :missing_item,
    :current_count,
    :required_count,
    :next_action
  ) do
    def complete?
      status == "complete"
    end

    def partial?
      status == "partial"
    end

    def pending?
      status == "pending"
    end

    def status_label
      {
        "complete" => "完了",
        "partial" => "一部完了",
        "pending" => "未着手"
      }.fetch(status)
    end
  end

  def levels
    [
      business_management_level,
      data_analysis_level,
      action_proposal_level,
      result_evaluation_level,
      evaluation_tuning_level,
      auto_execution_level,
      auto_pivot_level
    ]
  end

  private

  def business_management_level
    count = Business.count
    if count.positive?
      build(
        1,
        "事業管理",
        "complete",
        "事業フォルダと収益・代理指標を管理する土台",
        "事業登録済み",
        count,
        1,
        next_action("事業を見る", "/businesses", "登録済み事業の収益・代理指標を確認します")
      )
    else
      build(
        1,
        "事業管理",
        "pending",
        "事業フォルダと収益・代理指標を管理する土台",
        "Business未登録",
        count,
        1,
        next_action("事業を追加", "/businesses/new", "まずAICOOが見る事業を登録します")
      )
    end
  end

  def data_analysis_level
    count = BusinessMetricDaily.count + DataImport.count + AicooAnalyticsSite.count
    status = if count.positive?
      "complete"
    elsif Business.exists?
      "partial"
    else
      "pending"
    end
    missing_item = count.positive? ? "分析データあり" : "GA4/GSCまたは日次指標が不足"
    build(
      2,
      "データ分析",
      status,
      "GA4/GSC/DataHub/日次指標から事業状態を読む",
      missing_item,
      count,
      1,
      next_action("分析設定へ", "/admin/analytics_sites", "サイト別分析設定を確認します")
    )
  end

  def action_proposal_level
    count = ActionCandidate.count
    status = if count.positive?
      "complete"
    elsif Business.exists?
      "partial"
    else
      "pending"
    end
    missing_item = count.positive? ? "行動候補あり" : "ActionCandidate未生成"
    build(
      3,
      "行動提案",
      status,
      "ActionCandidateを生成し、総合・部門別に優先順位を出す",
      missing_item,
      count,
      1,
      next_action("候補を見る", "/action_candidates", "生成済み候補を確認し、必要なら追加します")
    )
  end

  def result_evaluation_level
    evaluated_count = ActionResult.evaluated.count
    status = if evaluated_count.positive?
      "complete"
    elsif ActionResult.exists?
      "partial"
    else
      "pending"
    end
    missing_item = if evaluated_count.positive?
      "評価済み結果あり"
    elsif ActionResult.exists?
      "評価待ちActionResultあり"
    else
      "ActionResult不足"
    end
    build(
      4,
      "結果評価",
      status,
      "ActionResultで予測と実績のズレを記録する",
      missing_item,
      evaluated_count,
      1,
      next_action("実行結果へ", "/action_results", "実行後の売上・利益・代理指標差分を記録します")
    )
  end

  def evaluation_tuning_level
    count = ActionCandidate.where(action_type: "evaluation_tuning").count
    status = if count.positive?
      "complete"
    elsif ActionResult.evaluated.exists?
      "partial"
    else
      "pending"
    end
    missing_item = if count.positive?
      "評価式改善候補あり"
    elsif ActionResult.evaluated.exists?
      "改善候補未生成"
    else
      "評価済みActionResult不足"
    end
    build(
      5,
      "評価式改善",
      status,
      "部門別精度から評価式の改善候補を出す",
      missing_item,
      count,
      1,
      next_action("部門別精度へ", "/department_rankings", "部門別のズレから評価式改善候補を作ります")
    )
  end

  def auto_execution_level
    done_count = AicooExecutorTask.done.count
    status = if done_count.positive?
      "complete"
    elsif AicooExecutorTask.exists?
      "partial"
    else
      "pending"
    end
    missing_item = if done_count.positive?
      "完了ExecutorTaskあり"
    elsif AicooExecutorTask.exists?
      "ExecutorTaskの完了不足"
    else
      "ExecutorTask未作成"
    end
    build(
      6,
      "自動実行",
      status,
      "Executorで実行指示を承認・実行・完了管理する",
      missing_item,
      done_count,
      1,
      next_action("実行指示へ", "/admin/aicoo_executor/tasks", "承認待ち・実行済みタスクを確認します")
    )
  end

  def auto_pivot_level
    count = ActionCandidate.where(action_type: %w[pivot withdraw]).count
    status = if count.positive? && ActionResult.evaluated.exists?
      "partial"
    else
      "pending"
    end
    missing_item = count.positive? ? "ピボット候補あり" : "自動ピボット未実装"
    build(
      7,
      "自動ピボット",
      status,
      "結果を見て継続・保留・撤退の判断まで進める",
      missing_item,
      count,
      1,
      next_action("将来実装", nil, "継続・撤退判断の自動化は次段階で扱います")
    )
  end

  def build(level, title, status, description, missing_item, current_count, required_count, next_action)
    Level.new(level:, title:, status:, description:, missing_item:, current_count:, required_count:, next_action:)
  end

  def next_action(label, path, reason)
    NextAction.new(label:, path:, reason:)
  end
end
