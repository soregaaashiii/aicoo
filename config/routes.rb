Rails.application.routes.draw do
  match "rails/action_mailbox", to: "blocked_internal_routes#not_found", via: :all
  match "rails/action_mailbox/*path", to: "blocked_internal_routes#not_found", via: :all
  match "rails/conductor/action_mailbox", to: "blocked_internal_routes#not_found", via: :all
  match "rails/conductor/action_mailbox/*path", to: "blocked_internal_routes#not_found", via: :all

  get "robots.txt", to: "robots#show", as: :robots
  get "sitemap.xml", to: "public_sitemaps#show", as: :sitemap, defaults: { format: :xml }
  namespace :api do
    namespace :aicoo do
      post "activity_logs", to: "activity_logs#create"
    end
  end
  root "public_landing_pages#index"
  get "lp", to: "public_landing_pages#index", as: :public_landing_pages
  get "public_lp", to: "public_landing_pages#index", as: :public_lp_index
  get "lp/:published_slug", to: "public_landing_pages#show", as: :public_lp
  post "lp/:published_slug/cta_click", to: "public_landing_pages#cta_click", as: :public_lp_cta_click
  post "lp/:published_slug/scroll", to: "public_landing_pages#scroll", as: :public_lp_scroll
  get "lp/:published_slug/signup", to: "public_landing_pages#new_signup", as: :public_lp_signup
  post "lp/:published_slug/signup", to: "public_landing_pages#create_signup"

  get "owner", to: "owner/dashboard#show", as: :owner_dashboard
  get "owner/dashboard", to: "owner/dashboard#show"
  get "owner/focus", to: "owner/focus#show", as: :owner_focus
  patch "owner/focus/defer", to: "owner/focus#defer", as: :defer_owner_focus
  patch "owner/focus/restore", to: "owner/focus#restore", as: :restore_owner_focus
  get "owner/tasks", to: "owner/tasks#index", as: :owner_tasks
  post "owner/serp_scan", to: "owner/serp_scans#create", as: :owner_serp_scan
  patch "owner/serp_scan_settings", to: "owner/serp_scans#update_settings", as: :owner_serp_scan_settings
  patch "owner/execution_queue_items/:id/complete", to: "owner/execution_queue_items#complete", as: :complete_owner_execution_queue_item
  patch "owner/execution_queue_items/:id/skip", to: "owner/execution_queue_items#skip", as: :skip_owner_execution_queue_item
  patch "owner/execution_queue_items/:id/restore", to: "owner/execution_queue_items#restore", as: :restore_owner_execution_queue_item
  get "owner/learning_report", to: "owner/learning_reports#show", as: :owner_learning_report
  get "owner/discovery_report", to: "owner/discovery_reports#show", as: :owner_discovery_report
  get "owner/explore/opportunities", to: "owner/opportunities#index", as: :owner_explore_opportunities
  post "owner/learning_recommendations/action_candidate", to: "owner/learning_recommendations#create_action_candidate", as: :create_action_candidate_owner_learning_recommendation
  post "owner/learning_recommendations/opportunity", to: "owner/learning_recommendations#create_opportunity", as: :create_opportunity_owner_learning_recommendation
  resources :opportunities, controller: "owner/opportunities", path: "owner/opportunities", as: :owner_opportunities, only: %i[index show new create] do
    get :focus, on: :collection
    patch :review, on: :member
    patch :approve, on: :member
    patch :reject, on: :member
    post :create_business, on: :member
    post :convert_to_candidate, on: :member
    patch :focus_approve, on: :member
    patch :focus_review, on: :member
    patch :focus_reject, on: :member
    post :focus_create_business, on: :member
    post :focus_convert_to_candidate, on: :member
  end
  patch "owner/calibrations/:id/approve", to: "owner/calibrations#approve", as: :approve_owner_calibration
  patch "owner/calibrations/:id/reject", to: "owner/calibrations#reject", as: :reject_owner_calibration
  get "owner/evaluator_trends", to: "owner/evaluator_trends#index", as: :owner_evaluator_trends
  get "owner/approved_queue", to: "owner/approved_queue#index", as: :owner_approved_queue
  post "owner/approved_queue/queue_selected", to: "owner/approved_queue#queue_selected", as: :queue_selected_owner_approved_queue
  post "owner/approved_queue/queue_all", to: "owner/approved_queue#queue_all", as: :queue_all_owner_approved_queue
  get "dashboard", to: "dashboard#show"
  post "dashboard/generate_ai_top10", to: "dashboard#generate_ai_top10", as: :generate_ai_top10_dashboard
  post "dashboard/import_business_metrics_today", to: "dashboard#import_business_metrics_today", as: :import_business_metrics_today_dashboard
  post "dashboard/import_business_metrics_yesterday", to: "dashboard#import_business_metrics_yesterday", as: :import_business_metrics_yesterday_dashboard
  post "dashboard/backfill_business_metrics", to: "dashboard#backfill_business_metrics", as: :backfill_business_metrics_dashboard
  post "dashboard/generate_action_candidates_from_metrics", to: "dashboard#generate_action_candidates_from_metrics", as: :generate_action_candidates_from_metrics_dashboard
  post "dashboard/generate_correction_readiness_actions", to: "dashboard#generate_correction_readiness_actions", as: :generate_correction_readiness_actions_dashboard
  post "dashboard/build_auto_revision_queue", to: "dashboard#build_auto_revision_queue", as: :build_auto_revision_queue_dashboard
  post "dashboard/refresh_system_mode_snapshot", to: "dashboard#refresh_system_mode_snapshot", as: :refresh_system_mode_snapshot_dashboard
  post "dashboard/generate_analysis_candidates", to: "dashboard#generate_analysis_candidates", as: :generate_analysis_candidates_dashboard
  post "dashboard/adjust_global_proxy_score_weights", to: "dashboard#adjust_global_proxy_score_weights", as: :adjust_global_proxy_score_weights_dashboard
  post "dashboard/adjust_all_business_proxy_score_weights", to: "dashboard#adjust_all_business_proxy_score_weights", as: :adjust_all_business_proxy_score_weights_dashboard
  get "department_rankings", to: "department_rankings#index"
  post "department_rankings/classify", to: "department_rankings#classify", as: :classify_department_rankings
  post "department_rankings/generate_evaluation_tuning", to: "department_rankings#generate_evaluation_tuning", as: :generate_evaluation_tuning_department_rankings

  resources :action_candidates do
    patch :approve, on: :member
    patch :reject, on: :member
    post :reevaluate_ai, on: :member
    post :send_to_executor, on: :member
    post :generate_codex_prompt_draft, on: :member
  end

  namespace :owner do
    resources :codex_prompt_drafts, only: %i[index show] do
      patch :approve, on: :member
      patch :reject, on: :member
      patch :mark_copied, on: :member
      patch :mark_executed, on: :member
    end
  end

  resources :action_results, only: %i[index show new create edit update] do
    post :evaluate, on: :member
  end
  resources :action_executions, only: :show do
    patch :start, on: :member
    patch :complete, on: :member
    patch :fail, on: :member
    patch :cancel, on: :member
  end
  resources :action_execution_logs, only: %i[show new create edit update]
  resources :codex_quality_checks, only: %i[index show] do
    patch :approve, on: :member
    patch :reject, on: :member
  end
  resources :auto_revision_tasks, only: %i[index show create] do
    get :codex_queue, on: :collection
    patch :approve, on: :member
    patch :cancel, on: :member
    patch :enqueue, on: :member
    patch :retry_execution, on: :member
    patch :mark_sent_to_codex, on: :member
    patch :start_implementation, on: :member
    patch :update_codex_tracking, on: :member
    patch :record_result, on: :member
    get :export_codex_prompt, on: :member
  end

  resources :revenue_events
  resources :business_metric_dailies
  resource :aicoo_setting, only: %i[show update]
  patch "aicoo_setting/data_sources", to: "aicoo_settings#update_data_sources", as: :update_data_sources_aicoo_setting
  resources :aicoo_daily_runs, only: %i[index show create] do
    resources :steps, only: [], controller: "aicoo_daily_run_steps" do
      post :recover, on: :member
    end
  end
  get "judge", to: "admin/aicoo_judge#show", as: :judge
  get "judge/action_predictions", to: "admin/aicoo_judge#action_predictions", as: :judge_action_predictions

  resources :businesses do
    post :promote_to_mvp, on: :member
    post :promote_to_production, on: :member
    post :promote_to_scaling, on: :member
    patch :update_resource_status, on: :member
    resources :business_services, only: %i[create update]
    post :generate_ai_candidates, on: :member
    post :import_google_api, on: :member
    post :import_gsc, on: :member
    post :import_ga4, on: :member
    get :google_settings, on: :member
    patch :google_settings, action: :update_google_settings, on: :member
    patch :update_data_source_settings, on: :member
    resources :data_imports, only: :create
    resources :serp_analyses, only: :create
  end

  namespace :aicoo_lab do
    get "previews/:preview_slug", to: "previews#show", as: :preview
    post "previews/:preview_slug/cta_click", to: "previews#cta_click", as: :preview_cta_click
    get "previews/:preview_slug/signup", to: "previews#new_signup", as: :preview_signup
    post "previews/:preview_slug/signup", to: "previews#create_signup"
    get "lp/:published_slug", to: "published_landing_pages#show", as: :published_lp
    post "lp/:published_slug/cta_click", to: "published_landing_pages#cta_click", as: :published_lp_cta_click
    get "lp/:published_slug/signup", to: "published_landing_pages#new_signup", as: :published_lp_signup
    post "lp/:published_slug/signup", to: "published_landing_pages#create_signup"
  end

  namespace :admin do
    get "explore", to: "explore#index", as: :explore
    get "explore/import", to: "explore_imports#new", as: :explore_import
    post "explore/import", to: "explore_imports#create"
    post "explore/import/preview", to: "explore_imports#preview", as: :explore_import_preview
    get "explore/observations/focus", to: "explore#focus", as: :explore_observations_focus
    post "explore/observations/:id/convert_to_opportunity", to: "explore#convert_to_opportunity", as: :explore_observation_convert_to_opportunity
    patch "explore/observations/:id/review", to: "explore#review_observation", as: :explore_observation_review
    patch "explore/observations/:id/reject", to: "explore#reject_observation", as: :explore_observation_reject
    patch "explore/observations/:id/hold", to: "explore#hold_observation", as: :explore_observation_hold
    resources :business_execution_profiles, except: %i[show destroy]
    resources :google_credentials, except: %i[show destroy] do
      get :connect, on: :member
    end
    resources :analytics_sites, except: %i[show destroy] do
      post :autolink, on: :collection
      member do
        post :fetch_gsc
        post :fetch_ga4
        post :fetch_all
      end
    end
    resources :analytics_connections, only: %i[index create] do
      post :fetch_gsc, on: :collection
      post :fetch_ga4, on: :collection
      post :fetch_all_for_business, on: :collection
      post :delete_credentials_json, on: :collection
    end
    get "analytics_oauth/connect", to: "analytics_oauth#connect", as: :analytics_oauth_connect
    get "analytics_oauth/callback", to: "analytics_oauth#callback", as: :analytics_oauth_callback
    get "google_api_imports", to: "google_api_imports#index", as: :google_api_imports
    post "google_api_imports", to: "google_api_imports#create"
    post "google_api_imports/:business_id", to: "google_api_imports#create", as: :google_api_import
    get "execution_runs", to: "execution_runs#index", as: :execution_runs
    get "execution_runs/:id", to: "execution_runs#show", as: :execution_run
    resources :external_commit_imports, only: %i[new create]
    get "cron_health", to: "aicoo_daily_run_health#show", as: :cron_health
    get "aicoo_daily_run_health", to: "aicoo_daily_run_health#show", as: :aicoo_daily_run_health
    get "pipeline_e2e_check", to: "pipeline_e2e_checks#show", as: :pipeline_e2e_check
    post "pipeline_e2e_check/repair", to: "pipeline_e2e_checks#repair", as: :pipeline_e2e_check_repair
    get "activity_learning_e2e_check", to: "activity_learning_e2e_checks#show", as: :activity_learning_e2e_check
    post "activity_learning_e2e_check/repair", to: "activity_learning_e2e_checks#repair", as: :activity_learning_e2e_check_repair
    resource :aicoo_resource_budget, only: %i[show update]
    resources :auto_build_tasks, only: %i[index show]
    post "pipeline_recoveries/:pipeline_run_id", to: "pipeline_recoveries#create", as: :pipeline_recovery
    patch "auto_revision_run_logs/:id/rollback", to: "auto_revision_run_logs#rollback", as: :auto_revision_run_log_rollback
    resources :idea_pipeline, controller: "idea_pipeline", only: %i[index show] do
      post :generate, on: :collection
      member do
        post :score
        post :run_serp
        post :generate_lp
        post :publish_lp
        post :evaluate_learning
        post :build_mvp_spec
        post :recover_business
        post :run_pipeline
      end
    end
    resource :serp_settings, only: %i[show update] do
      post :test_search
    end
    resources :analytics_imports, only: %i[index create] do
      post :reprocess, on: :member
    end
    resources :analytics_sources, controller: "analytics_sources" do
      post :fetch_all, on: :collection
      post :check_readiness, on: :collection
      post :fetch_now, on: :member
    end
    get "aicoo_revenue", to: "aicoo_revenue#show", as: :aicoo_revenue
    get "aicoo_executor", to: "aicoo_executor/tasks#index", as: :aicoo_executor
    get "codex_prompt_rules/preview", to: "codex_prompt_rules#preview", as: :codex_prompt_rules_preview
    post "codex_prompt_rules/preview", to: "codex_prompt_rules#preview"
    resources :codex_prompt_rules, only: %i[index edit update] do
      patch :toggle, on: :member
    end
    resources :business_activity_logs, only: %i[index show]
    resources :source_app_connections, only: %i[index edit update]
    resources :source_app_diff_rules, only: %i[index edit update]
    get "aicoo_datahub", to: "aicoo_datahub#show", as: :aicoo_datahub
    get "aicoo_judge", to: "aicoo_judge#show", as: :aicoo_judge
    get "aicoo_judge/action_predictions", to: "aicoo_judge#action_predictions", as: :aicoo_judge_action_predictions
    get "aicoo/calibration", to: "aicoo_calibration#index", as: :aicoo_calibration
    post "aicoo/calibration/recalculate", to: "aicoo_calibration#recalculate", as: :aicoo_calibration_recalculate
    patch "aicoo/calibration/:id/approve", to: "aicoo_calibration#approve", as: :aicoo_calibration_approve
    patch "aicoo/calibration/:id/reject", to: "aicoo_calibration#reject", as: :aicoo_calibration_reject
    get "aicoo_insights", to: "aicoo_insights#index", as: :aicoo_insights
    post "aicoo_insights/generate", to: "aicoo_insights#generate", as: :aicoo_insights_generate
    resource :aicoo_daily_run_settings, only: %i[show update]
    resource :aicoo_auto_revision_settings, only: %i[show update]
    post "aicoo_datahub/collect_landing_pages", to: "aicoo_datahub#collect_landing_pages", as: :aicoo_datahub_collect_landing_pages
    post "aicoo_datahub/collect_revenue", to: "aicoo_datahub#collect_revenue", as: :aicoo_datahub_collect_revenue
    post "aicoo_datahub/collect_data_imports", to: "aicoo_datahub#collect_data_imports", as: :aicoo_datahub_collect_data_imports
    post "aicoo_datahub/collect_all", to: "aicoo_datahub#collect_all", as: :aicoo_datahub_collect_all
    post "aicoo_datahub/run_daily_collection", to: "aicoo_datahub#run_daily_collection", as: :aicoo_datahub_run_daily_collection
    namespace :aicoo_executor, path: "aicoo_executor" do
      resources :tasks, only: %i[index show create] do
        member do
          patch :approve
          patch :reject
          patch :done
        end
      end
    end

    namespace :aicoo_revenue, path: "aicoo_revenue" do
      resources :executions, only: %i[index create show edit update] do
        member do
          patch :done
          patch :skipped
          patch :sync_action_candidate_done
        end
      end
    end

    namespace :aicoo_lab do
      root "experiments#index"
      get "approvals", to: "experiments#approvals", as: :approvals
      get "approved", to: "approved_experiments#index", as: :approved_experiments
      post "approved/bulk_running", to: "approved_experiments#bulk_running", as: :approved_experiments_bulk_running
      patch "approved/:experiment_id/running", to: "approved_experiments#running", as: :approved_experiment_running
      get "scoring_queue", to: "scoring_queue#index", as: :scoring_queue
      get "scoring_queue/:experiment_id/:target_days/snapshot", to: "scoring_queue#snapshot", as: :scoring_queue_snapshot
      post "scoring_queue/:experiment_id/:target_days/score_snapshot", to: "scoring_queue#score_snapshot", as: :scoring_queue_score_snapshot
      post "scoring_queue/:experiment_id/:target_days/score", to: "scoring_queue#score", as: :scoring_queue_score
      post "scoring_queue/:experiment_id/:target_days/hold", to: "scoring_queue#hold", as: :scoring_queue_hold
      post "scoring_queue/:experiment_id/:target_days/fail", to: "scoring_queue#fail", as: :scoring_queue_fail
      post "scoring_queue/:experiment_id/:target_days/reevaluate", to: "scoring_queue#reevaluate", as: :scoring_queue_reevaluate
      get "review_queue", to: "review_queue#index", as: :review_queue
      post "review_queue/bulk_update", to: "review_queue#bulk_update", as: :review_queue_bulk_update
      get "review_queue/:experiment_id", to: "review_queue#show", as: :review_queue_experiment
      patch "review_queue/:experiment_id/approval_pending", to: "review_queue#approval_pending", as: :review_queue_approval_pending
      patch "review_queue/:experiment_id/approve", to: "review_queue#approve", as: :review_queue_approve
      patch "review_queue/:experiment_id/reject", to: "review_queue#reject", as: :review_queue_reject
      patch "review_queue/:experiment_id/paused", to: "review_queue#paused", as: :review_queue_paused
      get "public_landing_pages", to: "public_landing_pages#index", as: :public_landing_pages
      get "public_landing_pages/new", to: "public_landing_pages#new", as: :new_public_landing_page
      post "public_landing_pages", to: "public_landing_pages#create"
      get "public_landing_pages/:id/edit", to: "public_landing_pages#edit", as: :edit_public_landing_page
      patch "public_landing_pages/:id", to: "public_landing_pages#update", as: :public_landing_page
      patch "public_landing_pages/:id/publish", to: "public_landing_pages#publish", as: :publish_public_landing_page
      post "public_landing_pages/:id/recover_business", to: "public_landing_pages#recover_business", as: :recover_public_landing_page_business
      get "serp_landing_page_candidates", to: "serp_landing_page_candidates#index", as: :serp_landing_page_candidates
      post "serp_landing_page_candidates", to: "serp_landing_page_candidates#create"
      post "serp_landing_page_candidates/:id/create_landing_page", to: "serp_landing_page_candidates#create_landing_page", as: :serp_landing_page_candidate_create_landing_page
      resource :setting, only: %i[ show update ]
      resources :generation_runs, only: %i[ index show ]
      resources :ai_candidate_imports, only: %i[ new create ]
      resources :ai_drafts, only: %i[ index new create show ] do
        member do
          patch :approve
          patch :reject
          post :import_candidates
        end
      end

      resources :candidates, controller: "experiment_candidates" do
        post :generate, on: :collection
        post :bulk_convert_with_landing_pages, on: :collection

        member do
          patch :approve
          patch :reject
          post :convert_to_experiment
          post :convert_to_experiment_with_landing_page
        end
      end

      resources :experiments do
        member do
          patch :preview_ready
          patch :approval_pending
          patch :approve
          patch :reject
          patch :running
          patch :paused
          patch :success
          patch :failed
          patch :reevaluate
          post :recalculate_errors
          post :create_30d_results_from_metrics
          post :create_90d_results_from_metrics
        end

        resources :predictions, only: :create
        resources :results, only: :create
        resource :landing_page, only: %i[ new create edit update ], controller: "landing_pages" do
          patch :preview_ready
          patch :publish
          patch :pause
          patch :resume
          patch :unpublish
        end
      end
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
end
