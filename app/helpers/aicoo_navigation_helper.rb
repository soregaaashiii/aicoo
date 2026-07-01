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
      instance_variable_get(:@auto_revision_task)&.business,
      instance_variable_get(:@business_activity_log)&.business,
      instance_variable_get(:@auto_build_task)&.business,
      instance_variable_get(:@action_execution)&.action_candidate&.business,
      instance_variable_get(:@action_execution_log)&.business
    ].compact.find { |business| business.respond_to?(:persisted?) ? business.persisted? : business.present? }
  end

  def aicoo_contextual_sidebar_category_key
    return :business if aicoo_context_business && aicoo_business_context_path?
    return :ai_activity if request.path.start_with?("/aicoo_daily_runs", "/auto_revision_tasks", "/admin/execution_runs")
    return :new_business if request.path.start_with?("/admin/idea_pipeline", "/admin/aicoo_lab")
    return :analysis if request.path.match?(%r{\A/admin/(analytics|google_api_imports|serp_settings)}) || request.path.start_with?("/business_metric_dailies")
    return :settings if request.path.match?(%r{\A/admin/(google_credentials|aicoo_daily_run_settings|aicoo_auto_revision_settings|business_execution_profiles|source_app_connections|source_app_diff_rules)}) || request.path.start_with?("/aicoo_setting")
    return :learning if request.path.match?(%r{\A/(action_results|judge|department_rankings)}) || request.path.match?(%r{\A/admin/(aicoo_judge|aicoo/calibration|business_activity_logs|activity_learning_e2e_check)})

    nil
  end

  def aicoo_contextual_sidebar_child_key
    return nil unless aicoo_contextual_sidebar_category_key == :business

    path = request.path
    return :business_improvements if path.match?(%r{\A/(action_candidates|action_executions|action_execution_logs|action_results|auto_revision_tasks)}) || path.match?(%r{\A/admin/business_activity_logs})
    return :business_numbers if path.match?(%r{\A/(revenue_events|business_metric_dailies)})

    :business_list
  end

  def aicoo_business_context_path?
    request.path.match?(%r{\A/(businesses|action_candidates|action_executions|action_execution_logs|action_results|revenue_events|business_metric_dailies|auto_revision_tasks)}) ||
      request.path.match?(%r{\A/admin/(business_activity_logs|auto_build_tasks)})
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
    return "改善履歴" if path.match?(%r{\A/(action_candidates|action_executions|action_execution_logs|action_results|auto_revision_tasks)}) || path.match?(%r{\A/admin/(business_activity_logs|auto_build_tasks)})
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
    elsif instance_variable_get(:@auto_revision_task)
      "自動改修詳細"
    elsif instance_variable_get(:@business_activity_log)
      "Activity詳細"
    elsif instance_variable_get(:@auto_build_task)
      "Auto Build詳細"
    elsif request.path.include?("google_settings")
      "Google連携"
    else
      "詳細"
    end
  end

  def aicoo_sidebar_categories
    [
      {
        key: :business,
        label: "事業",
        description: "事業ごとの状態",
        path: businesses_path,
        matchers: [
          %r{\A/businesses},
          %r{\A/owner(?:/dashboard)?\z},
          %r{\A/owner/focus},
          %r{\A/revenue_events}
        ],
        children: [
          { key: :business_today, label: "今日やること", description: "事業改善の優先順", path: owner_focus_path, matchers: [ %r{\A/owner(?:/dashboard)?\z}, %r{\A/owner/focus} ] },
          { key: :business_list, label: "事業一覧", description: "全事業の状態", path: businesses_path, matchers: [ %r{\A/businesses} ] },
          { key: :business_improvements, label: "改善履歴", description: "改善案・実行結果・自動改修", path: action_candidates_path, matchers: [ %r{\A/action_candidates}, %r{\A/action_results}, %r{\A/auto_revision_tasks}, %r{\A/admin/business_activity_logs} ] },
          { key: :business_numbers, label: "売上と数字", description: "売上履歴・詳細データ", path: revenue_events_path, matchers: [ %r{\A/revenue_events}, %r{\A/business_metric_dailies} ] }
        ]
      },
      {
        key: :ai_activity,
        label: "AI活動",
        description: "日次実行・自動探索・自動改修",
        path: aicoo_daily_runs_path,
        matchers: [
          %r{\A/aicoo_daily_runs},
          %r{\A/auto_revision_tasks},
          %r{\A/owner/tasks},
          %r{\A/owner/approved_queue},
          %r{\A/owner/codex_prompt_drafts},
          %r{\A/admin/execution_runs},
          %r{\A/admin/aicoo_executor}
        ],
        children: [
          { key: :ai_daily_run, label: "AI日次実行", description: "Daily RunとStep", path: aicoo_daily_runs_path, matchers: [ %r{\A/aicoo_daily_runs} ] },
          { key: :ai_revision, label: "自動改修", description: "Codex投入準備", path: codex_queue_auto_revision_tasks_path, matchers: [ %r{\A/auto_revision_tasks}, %r{\A/owner/codex_prompt_drafts}, %r{\A/admin/aicoo_executor} ] },
          { key: :ai_execution_history, label: "実行履歴", description: "処理結果を確認", path: admin_execution_runs_path, matchers: [ %r{\A/admin/execution_runs} ] },
          { key: :ai_approval, label: "承認待ち", description: "承認・結果入力", path: owner_tasks_path, matchers: [ %r{\A/owner/tasks}, %r{\A/owner/approved_queue}, %r{\A/owner/execution_queue_items} ] }
        ]
      },
      {
        key: :new_business,
        label: "新規事業 / Lab",
        description: "Idea・LP検証・MVP候補",
        path: admin_idea_pipeline_index_path,
        matchers: [
          %r{\A/admin/idea_pipeline},
          %r{\A/admin/aicoo_lab},
          %r{\A/owner/explore/opportunities},
          %r{\A/owner/opportunities},
          %r{\A/admin/auto_build_tasks}
        ],
        children: [
          { key: :idea_pipeline, label: "Idea Pipeline", description: "IdeaからMVPへ", path: admin_idea_pipeline_index_path, matchers: [ %r{\A/admin/idea_pipeline} ] },
          { key: :lab_lp, label: "LP検証", description: "公開LPと実験", path: admin_aicoo_lab_public_landing_pages_path, matchers: [ %r{\A/admin/aicoo_lab} ] },
          { key: :auto_build, label: "MVP候補", description: "Auto Build Queue", path: admin_auto_build_tasks_path, matchers: [ %r{\A/admin/auto_build_tasks} ] },
          { key: :opportunities, label: "新規候補", description: "発見した機会", path: owner_explore_opportunities_path, matchers: [ %r{\A/owner/(explore/opportunities|opportunities)} ] }
        ]
      },
      {
        key: :learning,
        label: "学習",
        description: "予測を改善",
        path: action_results_path,
        matchers: [
          %r{\A/action_results},
          %r{\A/judge},
          %r{\A/admin/aicoo_judge},
          %r{\A/admin/aicoo/calibration},
          %r{\A/admin/business_activity_logs},
          %r{\A/admin/activity_learning_e2e_check},
          %r{\A/owner/learning_report},
          %r{\A/owner/discovery_report},
          %r{\A/owner/evaluator_trends},
          %r{\A/department_rankings}
        ],
        children: [
          { key: :learning_results, label: "実行結果", description: "実績を登録", path: action_results_path, matchers: [ %r{\A/action_results} ] },
          { key: :learning_accuracy, label: "AI判断精度", description: "予測と実績", path: judge_action_predictions_path, matchers: [ %r{\A/judge}, %r{\A/admin/aicoo_judge}, %r{\A/owner/evaluator_trends}, %r{\A/department_rankings} ] },
          { key: :learning_activity, label: "Activity学習", description: "施策ログと評価", path: admin_business_activity_logs_path, matchers: [ %r{\A/admin/business_activity_logs}, %r{\A/admin/activity_learning_e2e_check} ] },
          { key: :learning_calibration, label: "判断精度補正", description: "補正・精度", path: owner_learning_report_path, matchers: [ %r{\A/admin/aicoo/calibration}, %r{\A/owner/learning_report}, %r{\A/owner/discovery_report} ] }
        ]
      },
      {
        key: :analysis,
        label: "分析",
        description: "GA4/GSC/SERPなど",
        path: admin_google_api_imports_path,
        matchers: [
          %r{\A/admin/(analytics|google_api_imports|serp_settings|aicoo_datahub)},
          %r{\A/business_metric_dailies}
        ],
        children: [
          { key: :analysis_google, label: "Google分析", description: "GA4/GSC取得", path: admin_google_api_imports_path, matchers: [ %r{\A/admin/(analytics|google_api_imports)} ] },
          { key: :analysis_serp, label: "SERP分析", description: "検索結果調査", path: admin_serp_settings_path, matchers: [ %r{\A/admin/serp_settings} ] },
          { key: :analysis_data, label: "詳細データ", description: "指標とDataHub", path: business_metric_dailies_path, matchers: [ %r{\A/business_metric_dailies}, %r{\A/admin/aicoo_datahub} ] }
        ]
      },
      {
        key: :settings,
        label: "設定",
        description: "API・Cron・Codex・安全設定",
        path: dashboard_path,
        matchers: [
          %r{\A/dashboard},
          %r{\A/admin/cron_health},
          %r{\A/admin/aicoo_daily_run_health},
          %r{\A/admin/pipeline_e2e_check},
          %r{\A/admin/(google_credentials|aicoo_daily_run_settings|aicoo_auto_revision_settings|business_execution_profiles|codex_prompt_rules|aicoo_resource_budget|explore)},
          %r{\A/admin/source_app_(connections|diff_rules)},
          %r{\A/aicoo_setting},
          %r{\A/codex_quality_checks}
        ],
        children: [
          { key: :settings_status, label: "状態を見る", description: "監視室", path: dashboard_path, matchers: [ %r{\A/dashboard}, %r{\A/codex_quality_checks} ] },
          { key: :settings_daily_run, label: "Cron / Daily Run", description: "定期実行設定", path: admin_cron_health_path, matchers: [ %r{\A/admin/(cron_health|aicoo_daily_run_health|aicoo_daily_run_settings)} ] },
          { key: :settings_loop, label: "1周チェック", description: "自動ループ確認", path: admin_pipeline_e2e_check_path, matchers: [ %r{\A/admin/pipeline_e2e_check} ] },
          { key: :settings_google, label: "Google連携", description: "OAuthとAPIキー", path: admin_google_credentials_path, matchers: [ %r{\A/admin/google_credentials} ] },
          { key: :settings_codex, label: "Codex設定", description: "実行先とPromptルール", path: admin_business_execution_profiles_path, matchers: [ %r{\A/admin/(business_execution_profiles|codex_prompt_rules|aicoo_auto_revision_settings)} ] },
          { key: :settings_resources, label: "Resource Budget", description: "予算とBuild制御", path: admin_aicoo_resource_budget_path, matchers: [ %r{\A/admin/aicoo_resource_budget} ] },
          { key: :settings_source, label: "外部連携差分", description: "DB変更検知", path: admin_source_app_connections_path, matchers: [ %r{\A/admin/source_app_(connections|diff_rules)} ] },
          { key: :settings_general, label: "全体設定", description: "API・安全設定", path: aicoo_setting_path, matchers: [ %r{\A/aicoo_setting}, %r{\A/admin/explore} ] }
        ]
      }
    ]
  end
end
