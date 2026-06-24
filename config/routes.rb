Rails.application.routes.draw do
  match "rails/action_mailbox", to: "blocked_internal_routes#not_found", via: :all
  match "rails/action_mailbox/*path", to: "blocked_internal_routes#not_found", via: :all
  match "rails/conductor/action_mailbox", to: "blocked_internal_routes#not_found", via: :all
  match "rails/conductor/action_mailbox/*path", to: "blocked_internal_routes#not_found", via: :all

  root "dashboard#show"
  get "owner", to: "owner/dashboard#show", as: :owner_dashboard
  get "owner/dashboard", to: "owner/dashboard#show"
  get "owner/focus", to: "owner/focus#show", as: :owner_focus
  get "owner/tasks", to: "owner/tasks#index", as: :owner_tasks
  get "owner/learning_report", to: "owner/learning_reports#show", as: :owner_learning_report
  get "owner/discovery_report", to: "owner/discovery_reports#show", as: :owner_discovery_report
  post "owner/learning_recommendations/action_candidate", to: "owner/learning_recommendations#create_action_candidate", as: :create_action_candidate_owner_learning_recommendation
  post "owner/learning_recommendations/opportunity", to: "owner/learning_recommendations#create_opportunity", as: :create_opportunity_owner_learning_recommendation
  resources :opportunities, controller: "owner/opportunities", path: "owner/opportunities", as: :owner_opportunities, only: %i[index show new create] do
    get :focus, on: :collection
    patch :review, on: :member
    patch :reject, on: :member
    post :convert_to_candidate, on: :member
    patch :focus_review, on: :member
    patch :focus_reject, on: :member
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
    patch :mark_sent_to_codex, on: :member
    patch :start_implementation, on: :member
    patch :update_codex_tracking, on: :member
    patch :record_result, on: :member
    get :export_codex_prompt, on: :member
  end

  resources :revenue_events
  resources :business_metric_dailies
  resource :aicoo_setting, only: %i[show update]
  resources :aicoo_daily_runs, only: %i[index show create] do
    resources :steps, only: [], controller: "aicoo_daily_run_steps" do
      post :recover, on: :member
    end
  end
  get "judge", to: "admin/aicoo_judge#show", as: :judge
  get "judge/action_predictions", to: "admin/aicoo_judge#action_predictions", as: :judge_action_predictions

  resources :businesses do
    post :generate_ai_candidates, on: :member
    post :import_gsc, on: :member
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
