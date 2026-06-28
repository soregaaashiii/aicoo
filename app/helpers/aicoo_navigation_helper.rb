module AicooNavigationHelper
  def aicoo_ceo_mode?
    request.path.start_with?("/owner")
  end

  def aicoo_mode_label
    aicoo_ceo_mode? ? "CEO MODE" : "SYSTEM MODE"
  end

  def aicoo_mode_description
    if aicoo_ceo_mode?
      "今日動くための意思決定画面"
    else
      "AICOO自身の運用・復旧画面"
    end
  end

  def aicoo_mode_home_path
    owner_focus_path
  end

  def aicoo_sidebar_items
    aicoo_sidebar_categories
  end

  def aicoo_current_section_label
    aicoo_current_sidebar_child&.fetch(:label) || aicoo_current_sidebar_category&.fetch(:label) || "現在の画面"
  end

  def aicoo_breadcrumb_items
    category = aicoo_current_sidebar_category
    child = aicoo_current_sidebar_child

    [
      { label: aicoo_mode_label, path: aicoo_mode_home_path },
      category && { label: category[:label], path: category[:path] },
      child && { label: child[:label], path: child[:path] }
    ].compact.uniq { |item| [ item[:label], item[:path] ] }
  end

  def aicoo_sidebar_category_active?(category)
    aicoo_path_matches?(category) || category.fetch(:children, []).any? { |child| aicoo_sidebar_child_active?(child) }
  end

  def aicoo_sidebar_child_active?(item)
    aicoo_path_matches?(item)
  end

  # Kept for older partials/tests that still call the old flat-sidebar helper.
  def aicoo_sidebar_active?(item)
    aicoo_sidebar_child_active?(item)
  end

  private

  def aicoo_current_sidebar_category
    aicoo_sidebar_categories.find { |category| aicoo_sidebar_category_active?(category) }
  end

  def aicoo_current_sidebar_child
    aicoo_current_sidebar_category&.fetch(:children, [])&.find { |child| aicoo_sidebar_child_active?(child) }
  end

  def aicoo_path_matches?(item)
    current_path = request.path
    item_path = item[:path].to_s.split("#").first.split("?").first
    explicit_path_match = current_path == item_path || (item_path != "/" && current_path.start_with?(item_path))
    matcher_match = item.fetch(:matchers, []).any? { |matcher| current_path.match?(matcher) }

    explicit_path_match || matcher_match
  end

  def aicoo_sidebar_categories
    [
      {
        key: :today,
        label: "今日やる",
        description: "今日見る場所",
        path: owner_focus_path,
        matchers: [
          %r{\A/owner(?:/dashboard)?\z},
          %r{\A/owner/focus},
          %r{\A/owner/tasks},
          %r{\A/aicoo_daily_runs}
        ],
        children: [
          { label: "今日の仕事", description: "最優先とランキング", path: owner_focus_path, matchers: [ %r{\A/owner(?:/dashboard)?\z}, %r{\A/owner/focus} ] },
          { label: "確認する", description: "承認・結果入力・警告", path: owner_tasks_path, matchers: [ %r{\A/owner/tasks}, %r{\A/owner/execution_queue_items} ] },
          { label: "自動実行を直す", description: "Daily Run再実行", path: aicoo_daily_runs_path, matchers: [ %r{\A/aicoo_daily_runs} ] }
        ]
      },
      {
        key: :business,
        label: "事業を見る",
        description: "事業ごとの状態",
        path: businesses_path,
        matchers: [
          %r{\A/businesses},
          %r{\A/business_metric_dailies},
          %r{\A/revenue_events}
        ],
        children: [
          { label: "事業一覧", description: "全事業の状態", path: businesses_path, matchers: [ %r{\A/businesses} ] },
          { label: "数字を見る", description: "収益・指標", path: business_metric_dailies_path, matchers: [ %r{\A/business_metric_dailies}, %r{\A/revenue_events} ] }
        ]
      },
      {
        key: :execution,
        label: "提案を動かす",
        description: "承認・実行",
        path: action_candidates_path,
        matchers: [
          %r{\A/action_candidates},
          %r{\A/action_executions},
          %r{\A/action_execution_logs},
          %r{\A/auto_revision_tasks},
          %r{\A/owner/approved_queue},
          %r{\A/owner/codex_prompt_drafts},
          %r{\A/admin/aicoo_executor}
        ],
        children: [
          { label: "提案を見る", description: "行動候補を確認", path: action_candidates_path, matchers: [ %r{\A/action_candidates} ] },
          { label: "承認済みを進める", description: "実行待ちキュー", path: owner_approved_queue_path, matchers: [ %r{\A/owner/approved_queue}, %r{\A/action_executions}, %r{\A/action_execution_logs} ] },
          { label: "Codexへ渡す", description: "改修タスク", path: codex_queue_auto_revision_tasks_path, matchers: [ %r{\A/auto_revision_tasks}, %r{\A/owner/codex_prompt_drafts}, %r{\A/admin/aicoo_executor} ] }
        ]
      },
      {
        key: :learning,
        label: "精度を育てる",
        description: "予測を改善",
        path: action_results_path,
        matchers: [
          %r{\A/action_results},
          %r{\A/judge},
          %r{\A/admin/aicoo_judge},
          %r{\A/admin/aicoo/calibration},
          %r{\A/owner/learning_report},
          %r{\A/owner/discovery_report},
          %r{\A/owner/evaluator_trends},
          %r{\A/department_rankings}
        ],
        children: [
          { label: "結果を入れる", description: "実績を登録", path: action_results_path, matchers: [ %r{\A/action_results} ] },
          { label: "ズレを見る", description: "予測と実績", path: judge_action_predictions_path, matchers: [ %r{\A/judge}, %r{\A/admin/aicoo_judge}, %r{\A/owner/evaluator_trends}, %r{\A/department_rankings} ] },
          { label: "学習を調整", description: "補正・精度", path: owner_learning_report_path, matchers: [ %r{\A/admin/aicoo/calibration}, %r{\A/owner/learning_report}, %r{\A/owner/discovery_report} ] }
        ]
      },
      {
        key: :system,
        label: "システムを直す",
        description: "連携・エラー",
        path: dashboard_path,
        matchers: [
          %r{\A/dashboard},
          %r{\A/admin/(analytics|google|aicoo_datahub|aicoo_daily_run_settings|aicoo_auto_revision_settings|business_execution_profiles|explore)},
          %r{\A/aicoo_setting},
          %r{\A/codex_quality_checks}
        ],
        children: [
          { label: "状態を見る", description: "エラーと実行状況", path: dashboard_path, matchers: [ %r{\A/dashboard}, %r{\A/codex_quality_checks} ] },
          { label: "Google連携", description: "GA4/GSC設定", path: admin_google_credentials_path, matchers: [ %r{\A/admin/(analytics|google)} ] },
          { label: "設定を直す", description: "API・安全設定", path: aicoo_setting_path, matchers: [ %r{\A/aicoo_setting}, %r{\A/admin/(aicoo_daily_run_settings|aicoo_auto_revision_settings|business_execution_profiles)} ] },
          { label: "詳しく診る", description: "データ・発見", path: admin_aicoo_datahub_path, matchers: [ %r{\A/admin/(aicoo_datahub|explore)} ] }
        ]
      }
    ]
  end
end
