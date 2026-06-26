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
      "AICOO自身の監視室"
    end
  end

  def aicoo_mode_home_path
    aicoo_ceo_mode? ? owner_focus_path : dashboard_path
  end

  def aicoo_sidebar_items
    aicoo_ceo_mode? ? aicoo_ceo_sidebar_items : aicoo_system_sidebar_items
  end

  def aicoo_current_section_label
    path = request.path

    case path
    when %r{\A/owner/focus\z}, %r{\A/owner\z}, %r{\A/owner/dashboard\z}
      "今日やること"
    when %r{\A/owner/tasks}
      "確認タスク"
    when %r{\A/owner/opportunities}, %r{\A/owner/explore}
      "発見と検証"
    when %r{\A/owner/learning_report}
      "学習状態"
    when %r{\A/owner/discovery_report}
      "発見源"
    when %r{\A/owner/codex_prompt_drafts}
      "Codex Prompts"
    when %r{\A/dashboard}
      "Daily Monitor"
    when %r{\A/aicoo_daily_runs}
      "Jobs"
    when %r{\A/admin/analytics}, %r{\A/admin/google_credentials}, %r{\A/admin/business_execution_profiles}
      "Integrations"
    when %r{\A/admin/explore}
      "Pipeline"
    when %r{\A/auto_revision_tasks}, %r{\A/codex_quality_checks}
      "Executor"
    when %r{\A/admin/aicoo/calibration}, %r{\A/department_rankings}, %r{\A/action_results}
      "Learning"
    when %r{\A/action_candidates}
      "ActionCandidate"
    when %r{\A/action_executions}
      "Execution"
    when %r{\A/businesses}
      "Business"
    when %r{\A/aicoo_setting}, %r{\A/admin/aicoo_daily_run_settings}, %r{\A/admin/aicoo_auto_revision_settings}
      "Settings"
    else
      controller_path.tr("/", " / ").titleize
    end
  end

  def aicoo_breadcrumb_items
    [
      { label: aicoo_mode_label, path: aicoo_mode_home_path },
      { label: aicoo_current_section_label, path: request.path }
    ]
  end

  def aicoo_sidebar_active?(item)
    current_path = request.path
    item_path = item[:path].to_s.split("#").first.split("?").first

    current_path == item_path || (item_path != "/" && current_path.start_with?(item_path))
  end

  private

  def aicoo_ceo_sidebar_items
    [
      { label: "今日", description: "次にやる1件", path: owner_focus_path },
      { label: "確認タスク", description: "承認・警告・復旧", path: owner_tasks_path },
      { label: "経営サマリー", description: "全体状況", path: owner_dashboard_path },
      { label: "発見と検証", description: "事業機会", path: owner_opportunities_path },
      { label: "学習状態", description: "判断の改善", path: owner_learning_report_path },
      { label: "発見源", description: "どこから見つかったか", path: owner_discovery_report_path },
      { label: "設定", description: "方針と安全設定", path: aicoo_setting_path }
    ]
  end

  def aicoo_system_sidebar_items
    [
      { label: "Daily Monitor", description: "Health / Pipeline", path: dashboard_path },
      { label: "Integrations", description: "GSC / GA4 / 認証", path: admin_analytics_sites_path },
      { label: "Pipeline", description: "Explore / DataHub", path: admin_explore_path },
      { label: "Jobs", description: "Daily Run / Steps", path: aicoo_daily_runs_path },
      { label: "Queues", description: "Owner / Codex queue", path: owner_tasks_path },
      { label: "Learning", description: "補正・精度・判断材料", path: admin_aicoo_calibration_path },
      { label: "Playbook", description: "事業別勝ちパターン", path: businesses_path },
      { label: "Executor", description: "Codex実行管理", path: codex_queue_auto_revision_tasks_path },
      { label: "Deep Diagnostics", description: "詳細診断", path: admin_aicoo_datahub_path },
      { label: "Settings", description: "Run / Queue / Guardrail", path: aicoo_setting_path }
    ]
  end
end
