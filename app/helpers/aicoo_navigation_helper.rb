module AicooNavigationHelper
  def aicoo_ceo_mode?
    request.path.match?(%r{\A/(owner|actions|businesses|action_candidates|auto_revision_tasks|revenue_events|action_results)}) ||
      request.path.start_with?("/admin/serp_settings")
  end

  def aicoo_mode_label
    aicoo_ceo_mode? ? "CEOモード" : "システムモード"
  end

  def aicoo_mode_description
    if aicoo_ceo_mode?
      "今日動くための意思決定画面"
    else
      "AICOO自身の運用・復旧画面"
    end
  end

  def aicoo_mode_home_path
    aicoo_ceo_mode? ? owner_focus_path : aicoo_daily_runs_path
  end

  def aicoo_sidebar_items
    aicoo_sidebar_categories
  end

  def aicoo_current_section_label
    aicoo_current_sidebar_child&.fetch(:label) || aicoo_current_sidebar_category&.fetch(:label) || "現在の画面"
  end

  def aicoo_breadcrumb_items
    return aicoo_action_workspace_breadcrumb_items if aicoo_action_workspace_path?
    return aicoo_business_context_breadcrumb_items if aicoo_context_business

    category = aicoo_current_sidebar_category
    child = aicoo_current_sidebar_child

    [
      { label: aicoo_mode_label, path: aicoo_mode_home_path },
      category && { label: category[:label], path: category[:path] },
      child && { label: child[:label], path: child[:path] }
    ].compact.uniq { |item| [ item[:label], item[:path] ] }
  end

  def aicoo_sidebar_category_active?(category)
    contextual_key = aicoo_contextual_sidebar_category_key
    return category[:key] == contextual_key if contextual_key

    aicoo_path_matches?(category) || category.fetch(:children, []).any? { |child| aicoo_sidebar_child_active?(child) }
  end

  def aicoo_sidebar_child_active?(item)
    contextual_child_key = aicoo_contextual_sidebar_child_key
    return item[:key] == contextual_child_key if contextual_child_key

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

  def aicoo_context_business
    @aicoo_context_business ||= [
      instance_variable_get(:@business),
      instance_variable_get(:@action_candidate)&.business,
      instance_variable_get(:@action_result)&.business,
      instance_variable_get(:@revenue_event)&.business,
      instance_variable_get(:@business_metric_daily)&.business,
      instance_variable_get(:@business_activity_log)&.business,
      instance_variable_get(:@auto_build_task)&.business,
      instance_variable_get(:@action_execution)&.action_candidate&.business,
      instance_variable_get(:@action_execution_log)&.business
    ].compact.find { |business| business.respond_to?(:persisted?) ? business.persisted? : business.present? }
  end

  def aicoo_contextual_sidebar_category_key
    return :ceo_mode if aicoo_ceo_mode?
    return :system_mode unless aicoo_ceo_mode?

    nil
  end

  def aicoo_contextual_sidebar_child_key
    return aicoo_ceo_sidebar_child_key if aicoo_contextual_sidebar_category_key == :ceo_mode
    return aicoo_system_sidebar_child_key if aicoo_contextual_sidebar_category_key == :system_mode

    nil
  end

  def aicoo_ceo_sidebar_child_key
    path = request.path
    return :ceo_businesses if aicoo_context_business && aicoo_business_context_path?
    return :ceo_home if path.match?(%r{\A/owner(?:/dashboard)?\z})
    return :ceo_today if path.start_with?("/owner/focus", "/actions/")
    return :ceo_serp if path.start_with?("/admin/serp_settings")
    return :ceo_businesses if path.start_with?("/businesses")
    return :ceo_overview if path.start_with?("/owner/auto_revision_loop", "/owner/new_business_pipeline", "/action_candidates", "/auto_revision_tasks", "/revenue_events", "/action_results")

    :ceo_home
  end

  def aicoo_system_sidebar_child_key
    path = request.path
    return :system_daily_runs if path.start_with?("/aicoo_daily_runs", "/admin/aicoo_daily_run_health")
    return :system_cron_health if path.start_with?("/admin/cron_health")
    return :system_google if path.start_with?("/admin/google_credentials", "/admin/google_api_imports", "/admin/analytics")
    return :system_traffic_channels if path.start_with?("/admin/traffic_channels")
    return :system_pipeline_e2e if path.start_with?("/admin/pipeline_e2e_check")
    return :system_activity_learning if path.start_with?("/admin/activity_learning_e2e_check", "/admin/business_activity_logs")
    return :system_datahub if path.start_with?("/admin/aicoo_datahub", "/business_metric_dailies")
    return :system_calibration if path.start_with?("/admin/aicoo/calibration")
    return :system_judge if path.start_with?("/judge", "/admin/aicoo_judge", "/department_rankings")
    return :system_resource_budget if path.start_with?("/admin/aicoo_resource_budget")
    return :system_source_app if path.start_with?("/admin/source_app_connections", "/admin/source_app_diff_rules")
    return :system_codex_connection if path.start_with?("/admin/codex_connection")
    return :system_approval_logs if path.start_with?("/admin/approval_logs")
    return :system_execution_profiles if path.start_with?("/admin/business_execution_profiles")
    return :system_codex_rules if path.start_with?("/admin/codex_prompt_rules")
    return :system_settings if path.start_with?("/aicoo_setting", "/admin/aicoo_daily_run_settings", "/admin/aicoo_auto_revision_settings")

    :system_daily_runs
  end

  def aicoo_business_context_path?
    return false if aicoo_action_workspace_path?

    request.path.match?(%r{\A/(businesses|action_candidates|action_executions|action_execution_logs|action_results|revenue_events|business_metric_dailies)}) ||
      request.path.match?(%r{\A/admin/(business_activity_logs|auto_build_tasks)})
  end

  def aicoo_action_workspace_path?
    request.path.match?(%r{\A/actions/\d+})
  end

  def aicoo_action_workspace_breadcrumb_items
    [
      { label: "今日やること", path: owner_focus_path },
      { label: "作業", path: request.path }
    ]
  end

  def aicoo_business_context_breadcrumb_items
    business = aicoo_context_business
    return [
      { label: "事業", path: businesses_path },
      { label: business.name, path: business_path(business) }
    ] if request.path == business_path(business)

    [
      { label: "事業", path: businesses_path },
      { label: business.name, path: business_path(business) },
      { label: aicoo_context_objective_label, path: aicoo_context_objective_path },
      { label: aicoo_context_detail_label, path: request.path }
    ].compact.uniq { |item| [ item[:label], item[:path] ] }
  end

  def aicoo_context_objective_label
    path = request.path
    return "改善履歴" if path.match?(%r{\A/(action_candidates|action_executions|action_execution_logs|action_results)}) || path.match?(%r{\A/admin/(business_activity_logs|auto_build_tasks)})
    return "売上" if path.start_with?("/revenue_events")
    return "分析データ" if path.start_with?("/business_metric_dailies")
    return "設定" if path.start_with?("/businesses") && path.include?("google_settings")

    "概要"
  end

  def aicoo_context_objective_path
    business = aicoo_context_business
    return unless business

    case aicoo_context_objective_label
    when "改善履歴"
      business_path(business, anchor: "business-improvements")
    when "売上"
      business_path(business, anchor: "business-revenue")
    when "分析データ"
      business_path(business, anchor: "analytics")
    when "設定"
      business_path(business, anchor: "business-settings")
    else
      business_path(business)
    end
  end

  def aicoo_context_detail_label
    if instance_variable_get(:@action_candidate)
      "改善案詳細"
    elsif instance_variable_get(:@action_execution)
      "実行準備詳細"
    elsif instance_variable_get(:@action_execution_log)
      "実行差分詳細"
    elsif instance_variable_get(:@action_result)
      "実行結果詳細"
    elsif instance_variable_get(:@revenue_event)
      "売上履歴詳細"
    elsif instance_variable_get(:@business_metric_daily)
      "詳細データ"
    elsif instance_variable_get(:@business_activity_log)
      "Activity詳細"
    elsif instance_variable_get(:@auto_build_task)
      "Auto Build詳細"
    elsif instance_variable_get(:@codex_submission)
      "Codex送信詳細"
    elsif request.path.include?("google_settings")
      "Google連携"
    else
      "詳細"
    end
  end

  def aicoo_sidebar_categories
    aicoo_ceo_mode? ? aicoo_ceo_sidebar_categories : aicoo_system_sidebar_categories
  end

  def aicoo_ceo_sidebar_categories
    [
      {
        key: :ceo_mode,
        label: "CEOモード",
        description: "今日どの事業を進めるか",
        path: owner_focus_path,
        matchers: [
          %r{\A/owner},
          %r{\A/businesses},
          %r{\A/action_candidates},
          %r{\A/auto_revision_tasks},
          %r{\A/admin/serp_settings},
          %r{\A/revenue_events},
          %r{\A/action_results}
        ],
        children: [
          { key: :ceo_home, label: "ホーム", description: "全体入口", path: owner_dashboard_path, matchers: [ %r{\A/owner(?:/dashboard)?\z} ] },
          { key: :ceo_today, label: "今日やること", description: "今日やる仕事", path: owner_focus_path, matchers: [ %r{\A/owner/focus}, %r{\A/actions/} ] },
          { key: :ceo_serp, label: "新規事業探索", description: "SERPで市場探索", path: admin_serp_settings_path, matchers: [ %r{\A/admin/serp_settings} ] },
          { key: :ceo_businesses, label: "事業一覧", description: "作成済み事業", path: businesses_path, matchers: [ %r{\A/businesses} ] },
          { key: :ceo_overview, label: "運用状況", description: "自動改修ループ", path: owner_auto_revision_loop_path, matchers: [ %r{\A/owner/(auto_revision_loop|new_business_pipeline)}, %r{\A/action_candidates}, %r{\A/auto_revision_tasks}, %r{\A/revenue_events}, %r{\A/action_results} ] }
        ]
      }
    ]
  end

  def aicoo_system_sidebar_categories
    [
      {
        key: :system_mode,
        label: "システムモード",
        description: "AICOOの運用・復旧",
        path: aicoo_daily_runs_path,
        matchers: [
          %r{\A/aicoo_daily_runs},
          %r{\A/admin},
          %r{\A/judge},
          %r{\A/department_rankings},
          %r{\A/business_metric_dailies},
          %r{\A/aicoo_setting}
        ],
        children: [
          { key: :system_daily_runs, label: "日次実行", description: "Daily RunとStep", path: aicoo_daily_runs_path, matchers: [ %r{\A/aicoo_daily_runs}, %r{\A/admin/aicoo_daily_run_health} ] },
          { key: :system_cron_health, label: "Cron監視", description: "Cron稼働確認", path: admin_cron_health_path, matchers: [ %r{\A/admin/cron_health} ] },
          { key: :system_google, label: "Google連携", description: "OAuthとGA4/GSC取得", path: admin_google_credentials_path, matchers: [ %r{\A/admin/(google_credentials|google_api_imports|analytics)} ] },
          { key: :system_traffic_channels, label: "集客監視", description: "集客チャネル全体", path: admin_traffic_channels_path, matchers: [ %r{\A/admin/traffic_channels} ] },
          { key: :system_pipeline_e2e, label: "自動ループ診断", description: "処理経路の診断", path: admin_pipeline_e2e_check_path, matchers: [ %r{\A/admin/pipeline_e2e_check} ] },
          { key: :system_activity_learning, label: "活動学習", description: "Activity検知と評価", path: admin_activity_learning_e2e_check_path, matchers: [ %r{\A/admin/(activity_learning_e2e_check|business_activity_logs)} ] },
          { key: :system_datahub, label: "データ基盤", description: "収集データ確認", path: admin_aicoo_datahub_path, matchers: [ %r{\A/admin/aicoo_datahub}, %r{\A/business_metric_dailies} ] },
          { key: :system_calibration, label: "期待値補正", description: "判断の補正", path: admin_aicoo_calibration_path, matchers: [ %r{\A/admin/aicoo/calibration} ] },
          { key: :system_judge, label: "判断精度", description: "AI判断の成績", path: judge_action_predictions_path, matchers: [ %r{\A/judge}, %r{\A/admin/aicoo_judge}, %r{\A/department_rankings} ] },
          { key: :system_resource_budget, label: "AI予算", description: "AI予算とBuild制御", path: admin_aicoo_resource_budget_path, matchers: [ %r{\A/admin/aicoo_resource_budget} ] },
          { key: :system_source_app, label: "外部DB連携", description: "外部DB差分検知", path: admin_source_app_connections_path, matchers: [ %r{\A/admin/source_app_(connections|diff_rules)} ] },
          { key: :system_codex_connection, label: "Codex連携", description: "GitHub/PR連携", path: admin_codex_connection_path, matchers: [ %r{\A/admin/codex_connection} ] },
          { key: :system_approval_logs, label: "操作履歴", description: "承認・操作ログ", path: admin_approval_logs_path, matchers: [ %r{\A/admin/approval_logs} ] },
          { key: :system_settings, label: "全体設定", description: "AICOO設定", path: aicoo_setting_path, matchers: [ %r{\A/aicoo_setting}, %r{\A/admin/(aicoo_daily_run_settings|aicoo_auto_revision_settings)} ] },
          { key: :system_execution_profiles, label: "実行先設定", description: "実行環境の設定", path: admin_business_execution_profiles_path, matchers: [ %r{\A/admin/business_execution_profiles} ] },
          { key: :system_codex_rules, label: "Codexルール", description: "Prompt共通ルール", path: admin_codex_prompt_rules_path, matchers: [ %r{\A/admin/codex_prompt_rules} ] }
        ]
      }
    ]
  end
end
