# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_23_132000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "action_candidate_score_snapshots", force: :cascade do |t|
    t.bigint "action_candidate_id", null: false
    t.decimal "action_type_accuracy"
    t.integer "adjusted_rank", null: false
    t.decimal "adjustment_multiplier", default: "1.0", null: false
    t.decimal "business_error_rate"
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.decimal "generation_source_accuracy"
    t.decimal "judge_adjusted_score", default: "0.0", null: false
    t.integer "rank_delta", null: false
    t.integer "raw_rank", null: false
    t.decimal "raw_score", default: "0.0", null: false
    t.text "reason"
    t.date "recorded_on", null: false
    t.datetime "updated_at", null: false
    t.index ["action_candidate_id", "recorded_on"], name: "idx_action_score_snapshots_unique_candidate_date", unique: true
    t.index ["action_candidate_id"], name: "index_action_candidate_score_snapshots_on_action_candidate_id"
    t.index ["adjustment_multiplier"], name: "idx_on_adjustment_multiplier_60019fcb76"
    t.index ["business_id"], name: "index_action_candidate_score_snapshots_on_business_id"
    t.index ["rank_delta"], name: "index_action_candidate_score_snapshots_on_rank_delta"
    t.index ["recorded_on"], name: "index_action_candidate_score_snapshots_on_recorded_on"
  end

  create_table "action_candidates", force: :cascade do |t|
    t.string "action_type"
    t.datetime "approved_at"
    t.string "approved_by"
    t.bigint "business_id", null: false
    t.integer "confidence_score"
    t.integer "cost_yen"
    t.datetime "created_at", null: false
    t.integer "data_confidence_score"
    t.string "department", default: "general", null: false
    t.text "description"
    t.integer "estimated_neglect_loss_90d_yen", default: 0, null: false
    t.text "evaluation_reason"
    t.text "execution_prompt"
    t.datetime "executor_queued_at"
    t.integer "expected_hourly_value_yen"
    t.decimal "expected_hours"
    t.integer "expected_learning_value_yen", default: 0, null: false
    t.integer "expected_profit_yen"
    t.integer "expected_revenue_value_yen", default: 0, null: false
    t.integer "expected_total_value_yen", default: 0, null: false
    t.integer "final_confidence_score", default: 0, null: false
    t.integer "final_expected_value_yen", default: 0, null: false
    t.decimal "final_score"
    t.string "generation_source", default: "manual", null: false
    t.integer "immediate_value_yen"
    t.jsonb "metadata", default: {}, null: false
    t.integer "neglect_loss_90d_yen", default: 0, null: false
    t.boolean "neglect_loss_auto_generated", default: false, null: false
    t.text "neglect_loss_reason"
    t.integer "priority_score"
    t.integer "risk_reduction_score"
    t.decimal "roi"
    t.string "status"
    t.integer "strategic_value_score"
    t.decimal "success_probability"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_action_candidates_on_business_id"
    t.index ["department"], name: "index_action_candidates_on_department"
    t.index ["generation_source"], name: "index_action_candidates_on_generation_source"
  end

  create_table "action_execution_logs", force: :cascade do |t|
    t.bigint "action_candidate_id", null: false
    t.bigint "action_result_id"
    t.text "actual_action", null: false
    t.decimal "actual_quantity"
    t.bigint "business_id", null: false
    t.decimal "completion_rate"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.text "human_note"
    t.jsonb "metadata", default: {}, null: false
    t.text "planned_action", null: false
    t.decimal "planned_quantity"
    t.bigint "revenue_event_id"
    t.datetime "started_at"
    t.string "status", default: "completed", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.decimal "variance_quantity"
    t.text "variance_reason"
    t.index ["action_candidate_id"], name: "index_action_execution_logs_on_action_candidate_id"
    t.index ["action_result_id"], name: "index_action_execution_logs_on_action_result_id"
    t.index ["business_id"], name: "index_action_execution_logs_on_business_id"
    t.index ["finished_at"], name: "index_action_execution_logs_on_finished_at"
    t.index ["revenue_event_id"], name: "index_action_execution_logs_on_revenue_event_id"
    t.index ["started_at"], name: "index_action_execution_logs_on_started_at"
    t.index ["status"], name: "index_action_execution_logs_on_status"
    t.index ["user_id"], name: "index_action_execution_logs_on_user_id"
  end

  create_table "action_prediction_calibration_logs", force: :cascade do |t|
    t.string "action_type", null: false
    t.bigint "aicoo_daily_run_id"
    t.decimal "avg_actual_profit_yen"
    t.decimal "avg_predicted_profit_yen"
    t.decimal "avg_profit_error_rate"
    t.datetime "calculated_at"
    t.datetime "created_at", null: false
    t.decimal "new_probability_calibration_factor"
    t.decimal "new_profit_calibration_factor"
    t.decimal "old_probability_calibration_factor"
    t.decimal "old_profit_calibration_factor"
    t.integer "sample_count"
    t.string "source", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.index ["action_type"], name: "index_action_prediction_calibration_logs_on_action_type"
    t.index ["aicoo_daily_run_id"], name: "index_action_prediction_calibration_logs_on_aicoo_daily_run_id"
    t.index ["calculated_at"], name: "index_action_prediction_calibration_logs_on_calculated_at"
    t.index ["source"], name: "index_action_prediction_calibration_logs_on_source"
  end

  create_table "action_prediction_calibrations", force: :cascade do |t|
    t.string "action_type", null: false
    t.decimal "actual_success_rate"
    t.text "approval_note"
    t.datetime "approval_requested_at"
    t.string "approval_status", default: "auto_applied", null: false
    t.datetime "approved_at"
    t.decimal "approved_probability_calibration_factor"
    t.decimal "approved_profit_calibration_factor"
    t.decimal "avg_actual_profit_yen"
    t.decimal "avg_predicted_profit_yen"
    t.decimal "avg_predicted_success_probability"
    t.decimal "avg_profit_error_rate"
    t.string "confidence_level", default: "low", null: false
    t.datetime "created_at", null: false
    t.datetime "factor_changed_at"
    t.datetime "last_calculated_at"
    t.decimal "pending_probability_calibration_factor"
    t.decimal "pending_profit_calibration_factor"
    t.decimal "previous_probability_calibration_factor"
    t.decimal "previous_profit_calibration_factor"
    t.decimal "probability_calibration_factor", default: "1.0", null: false
    t.decimal "profit_calibration_factor", default: "1.0", null: false
    t.datetime "rejected_at"
    t.integer "sample_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "warning_level", default: "none", null: false
    t.text "warning_reason"
    t.index ["action_type"], name: "index_action_prediction_calibrations_on_action_type", unique: true
    t.index ["approval_status"], name: "index_action_prediction_calibrations_on_approval_status"
    t.index ["confidence_level"], name: "index_action_prediction_calibrations_on_confidence_level"
    t.index ["warning_level"], name: "index_action_prediction_calibrations_on_warning_level"
  end

  create_table "action_results", force: :cascade do |t|
    t.bigint "action_candidate_id", null: false
    t.integer "actual_affiliate_clicks_delta", default: 0, null: false
    t.integer "actual_clicks_delta", default: 0, null: false
    t.integer "actual_impressions_delta", default: 0, null: false
    t.integer "actual_map_clicks_delta", default: 0, null: false
    t.integer "actual_pageviews_delta", default: 0, null: false
    t.integer "actual_phone_clicks_delta", default: 0, null: false
    t.integer "actual_profit_yen", default: 0, null: false
    t.decimal "actual_proxy_score_delta", default: "0.0", null: false
    t.integer "actual_revenue_yen", default: 0, null: false
    t.integer "actual_sessions_delta", default: 0, null: false
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.date "evaluated_on", null: false
    t.string "evaluation_status", default: "pending", null: false
    t.date "executed_on", null: false
    t.text "note"
    t.integer "predicted_expected_profit_yen"
    t.decimal "predicted_success_probability"
    t.integer "predicted_value_yen"
    t.decimal "prediction_error_rate"
    t.integer "prediction_error_yen"
    t.datetime "updated_at", null: false
    t.index ["action_candidate_id"], name: "index_action_results_on_action_candidate_id", unique: true
    t.index ["business_id"], name: "index_action_results_on_business_id"
    t.index ["evaluated_on"], name: "index_action_results_on_evaluated_on"
    t.index ["evaluation_status"], name: "index_action_results_on_evaluation_status"
  end

  create_table "ai_evaluation_runs", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.integer "created_action_count"
    t.datetime "created_at", null: false
    t.text "input_data"
    t.string "model_name"
    t.text "prompt"
    t.text "raw_response"
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_ai_evaluation_runs_on_business_id"
  end

  create_table "aicoo_analytics_sites", force: :cascade do |t|
    t.string "authentication_mode", default: "shared", null: false
    t.boolean "auto_created", default: false, null: false
    t.integer "autolink_source_id"
    t.string "autolink_source_type"
    t.bigint "business_id"
    t.datetime "created_at", null: false
    t.string "domain"
    t.boolean "enabled", default: true, null: false
    t.string "ga4_property_id"
    t.string "gsc_site_url"
    t.datetime "last_ga4_fetch_at"
    t.datetime "last_gsc_fetch_at"
    t.string "name", null: false
    t.text "notes"
    t.string "public_url"
    t.datetime "updated_at", null: false
    t.index ["authentication_mode"], name: "index_aicoo_analytics_sites_on_authentication_mode"
    t.index ["auto_created"], name: "index_aicoo_analytics_sites_on_auto_created"
    t.index ["autolink_source_type", "autolink_source_id"], name: "idx_analytics_sites_on_autolink_source"
    t.index ["business_id"], name: "index_aicoo_analytics_sites_on_business_id"
    t.index ["domain"], name: "index_aicoo_analytics_sites_on_domain"
    t.index ["ga4_property_id"], name: "index_aicoo_analytics_sites_on_ga4_property_id"
    t.index ["gsc_site_url"], name: "index_aicoo_analytics_sites_on_gsc_site_url"
  end

  create_table "aicoo_daily_run_settings", force: :cascade do |t|
    t.boolean "catch_up_enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "last_checked_at"
    t.datetime "last_success_at"
    t.integer "max_retry_per_day", default: 10, null: false
    t.boolean "retry_until_success", default: true, null: false
    t.integer "run_hour", default: 8, null: false
    t.integer "run_minute", default: 0, null: false
    t.string "timezone", default: "Asia/Tokyo", null: false
    t.datetime "updated_at", null: false
  end

  create_table "aicoo_daily_runs", force: :cascade do |t|
    t.integer "action_candidates_generated_count", default: 0, null: false
    t.integer "action_results_evaluated_count", default: 0, null: false
    t.integer "analytics_fetch_count", default: 0, null: false
    t.integer "business_metrics_imported_count", default: 0, null: false
    t.text "calibration_error"
    t.datetime "calibration_finished_at"
    t.integer "calibration_log_count", default: 0, null: false
    t.boolean "calibration_ran", default: false, null: false
    t.datetime "calibration_started_at"
    t.datetime "created_at", null: false
    t.integer "data_preparation_auto_queued_count", default: 0, null: false
    t.integer "data_preparation_candidates_count", default: 0, null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.integer "insight_generated_count", default: 0, null: false
    t.integer "pending_calibration_count", default: 0, null: false
    t.integer "proxy_weights_adjusted_count", default: 0, null: false
    t.integer "retry_count", default: 0, null: false
    t.text "run_log"
    t.integer "score_snapshot_no_adjustment_count", default: 0, null: false
    t.integer "score_snapshot_rank_down_count", default: 0, null: false
    t.integer "score_snapshot_rank_up_count", default: 0, null: false
    t.integer "score_snapshots_created_count", default: 0, null: false
    t.integer "snapshot_count", default: 0, null: false
    t.string "source", default: "manual", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.date "target_date", null: false
    t.datetime "updated_at", null: false
    t.integer "updated_calibration_count", default: 0, null: false
    t.index ["source"], name: "index_aicoo_daily_runs_on_source"
    t.index ["target_date", "status"], name: "index_aicoo_daily_runs_on_target_date_and_status"
    t.index ["target_date"], name: "index_aicoo_daily_runs_on_target_date"
  end

  create_table "aicoo_data_hub_collection_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "snapshot_count", default: 0, null: false
    t.datetime "started_at", null: false
    t.string "status", default: "running", null: false
    t.datetime "updated_at", null: false
    t.index ["started_at"], name: "index_aicoo_data_hub_collection_runs_on_started_at"
    t.index ["status"], name: "index_aicoo_data_hub_collection_runs_on_status"
  end

  create_table "aicoo_data_snapshots", force: :cascade do |t|
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.jsonb "payload", default: {}, null: false
    t.integer "source_id", null: false
    t.string "source_type", null: false
    t.datetime "updated_at", null: false
    t.index ["captured_at"], name: "index_aicoo_data_snapshots_on_captured_at"
    t.index ["source_type", "source_id"], name: "index_aicoo_data_snapshots_on_source_type_and_source_id"
    t.index ["source_type"], name: "index_aicoo_data_snapshots_on_source_type"
  end

  create_table "aicoo_executor_tasks", force: :cascade do |t|
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "done_at"
    t.integer "estimated_minutes"
    t.text "execution_prompt"
    t.string "execution_type", null: false
    t.integer "source_id", null: false
    t.string "source_type", null: false
    t.string "status", default: "draft", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_at"], name: "index_aicoo_executor_tasks_on_approved_at"
    t.index ["done_at"], name: "index_aicoo_executor_tasks_on_done_at"
    t.index ["execution_type"], name: "index_aicoo_executor_tasks_on_execution_type"
    t.index ["source_type", "source_id"], name: "index_aicoo_executor_tasks_on_source_type_and_source_id"
    t.index ["status"], name: "index_aicoo_executor_tasks_on_status"
  end

  create_table "aicoo_google_credentials", force: :cascade do |t|
    t.text "client_id"
    t.text "client_secret"
    t.datetime "connected_at"
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.text "notes"
    t.text "refresh_token"
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_aicoo_google_credentials_on_enabled"
  end

  create_table "aicoo_insight_generation_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.integer "generated_count", default: 0, null: false
    t.integer "skipped_count", default: 0, null: false
    t.string "source", default: "manual", null: false
    t.datetime "started_at", null: false
    t.string "status", default: "running", null: false
    t.datetime "updated_at", null: false
    t.index ["source"], name: "index_aicoo_insight_generation_runs_on_source"
    t.index ["started_at"], name: "index_aicoo_insight_generation_runs_on_started_at"
    t.index ["status"], name: "index_aicoo_insight_generation_runs_on_status"
  end

  create_table "aicoo_lab_ai_drafts", force: :cascade do |t|
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.bigint "generation_run_id", null: false
    t.datetime "imported_at"
    t.jsonb "parsed_json", default: {}, null: false
    t.text "raw_response"
    t.string "status", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_aicoo_lab_ai_drafts_on_created_at"
    t.index ["generation_run_id"], name: "index_aicoo_lab_ai_drafts_on_generation_run_id"
    t.index ["status"], name: "index_aicoo_lab_ai_drafts_on_status"
  end

  create_table "aicoo_lab_error_metrics", force: :cascade do |t|
    t.decimal "absolute_error"
    t.bigint "aicoo_lab_experiment_id", null: false
    t.bigint "aicoo_lab_prediction_id", null: false
    t.bigint "aicoo_lab_result_id", null: false
    t.datetime "calculated_at", null: false
    t.decimal "calibration_score"
    t.datetime "created_at", null: false
    t.decimal "error_rate"
    t.datetime "updated_at", null: false
    t.index ["aicoo_lab_experiment_id"], name: "index_aicoo_lab_error_metrics_on_aicoo_lab_experiment_id"
    t.index ["aicoo_lab_prediction_id", "aicoo_lab_result_id"], name: "index_lab_error_metrics_on_prediction_and_result", unique: true
    t.index ["aicoo_lab_prediction_id"], name: "index_aicoo_lab_error_metrics_on_aicoo_lab_prediction_id"
    t.index ["aicoo_lab_result_id"], name: "index_aicoo_lab_error_metrics_on_aicoo_lab_result_id"
  end

  create_table "aicoo_lab_experiment_candidates", force: :cascade do |t|
    t.string "acquisition_channel", null: false
    t.integer "assumed_price_yen"
    t.integer "budget_yen"
    t.bigint "converted_experiment_id"
    t.datetime "created_at", null: false
    t.integer "cta_count"
    t.text "description"
    t.integer "development_minutes"
    t.integer "estimated_neglect_loss_90d_yen", default: 0, null: false
    t.integer "estimated_work_minutes"
    t.integer "expected_90d_profit_yen"
    t.text "expected_learning"
    t.decimal "expected_value_score"
    t.string "experiment_type", null: false
    t.integer "feature_count"
    t.string "generation_source", default: "manual", null: false
    t.text "hypothesis"
    t.decimal "lab_priority_score"
    t.integer "lp_word_count"
    t.string "market_category"
    t.integer "neglect_loss_90d_yen", default: 0, null: false
    t.boolean "neglect_loss_auto_generated", default: false, null: false
    t.text "neglect_loss_reason"
    t.text "problem_statement"
    t.text "rationale"
    t.text "rejection_condition"
    t.decimal "scoring_speed_score"
    t.string "status", default: "proposed", null: false
    t.decimal "success_probability"
    t.string "target_user"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.text "validation_method"
    t.index ["acquisition_channel"], name: "index_aicoo_lab_experiment_candidates_on_acquisition_channel"
    t.index ["experiment_type"], name: "index_aicoo_lab_experiment_candidates_on_experiment_type"
    t.index ["generation_source"], name: "index_aicoo_lab_experiment_candidates_on_generation_source"
    t.index ["lab_priority_score"], name: "index_aicoo_lab_experiment_candidates_on_lab_priority_score"
    t.index ["market_category"], name: "index_aicoo_lab_experiment_candidates_on_market_category"
    t.index ["status"], name: "index_aicoo_lab_experiment_candidates_on_status"
  end

  create_table "aicoo_lab_experiments", force: :cascade do |t|
    t.string "acquisition_channel", null: false
    t.integer "actual_cost_yen"
    t.integer "actual_work_minutes"
    t.string "approval_status", default: "not_required", null: false
    t.integer "assumed_price_yen"
    t.integer "budget_yen"
    t.datetime "created_at", null: false
    t.string "created_by"
    t.integer "cta_count"
    t.integer "current_pv", default: 0, null: false
    t.text "description"
    t.integer "development_minutes"
    t.integer "estimated_neglect_loss_90d_yen", default: 0, null: false
    t.integer "estimated_work_minutes"
    t.integer "expected_90d_profit_yen"
    t.decimal "expected_value_score"
    t.string "experiment_type", null: false
    t.integer "feature_count"
    t.decimal "lab_priority_score"
    t.decimal "learning_value_score", default: "1.0", null: false
    t.integer "lp_word_count"
    t.string "market_category"
    t.integer "neglect_loss_90d_yen", default: 0, null: false
    t.boolean "neglect_loss_auto_generated", default: false, null: false
    t.text "neglect_loss_reason"
    t.text "notes"
    t.string "preview_url"
    t.string "public_url"
    t.datetime "published_at"
    t.integer "sample_pv_threshold", default: 1000, null: false
    t.datetime "score_due_30d_at"
    t.datetime "score_due_7d_at"
    t.datetime "score_due_90d_at"
    t.datetime "scored_30d_at"
    t.datetime "scored_7d_at"
    t.datetime "scored_90d_at"
    t.decimal "scoring_speed_score"
    t.datetime "started_at"
    t.string "status", default: "draft", null: false
    t.decimal "success_probability"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["acquisition_channel"], name: "index_aicoo_lab_experiments_on_acquisition_channel"
    t.index ["approval_status"], name: "index_aicoo_lab_experiments_on_approval_status"
    t.index ["experiment_type"], name: "index_aicoo_lab_experiments_on_experiment_type"
    t.index ["lab_priority_score"], name: "index_aicoo_lab_experiments_on_lab_priority_score"
    t.index ["market_category"], name: "index_aicoo_lab_experiments_on_market_category"
    t.index ["status"], name: "index_aicoo_lab_experiments_on_status"
  end

  create_table "aicoo_lab_generation_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.integer "generated_count", default: 0, null: false
    t.string "generation_type", null: false
    t.jsonb "metadata", default: {}, null: false
    t.text "prompt"
    t.text "response"
    t.datetime "started_at"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_aicoo_lab_generation_runs_on_created_at"
    t.index ["generation_type"], name: "index_aicoo_lab_generation_runs_on_generation_type"
    t.index ["status"], name: "index_aicoo_lab_generation_runs_on_status"
  end

  create_table "aicoo_lab_landing_page_events", force: :cascade do |t|
    t.bigint "aicoo_lab_landing_page_id", null: false
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "ip_hash"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.text "referrer"
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["aicoo_lab_landing_page_id"], name: "idx_on_aicoo_lab_landing_page_id_5195b6700d"
    t.index ["event_type"], name: "index_aicoo_lab_landing_page_events_on_event_type"
    t.index ["occurred_at"], name: "index_aicoo_lab_landing_page_events_on_occurred_at"
  end

  create_table "aicoo_lab_landing_pages", force: :cascade do |t|
    t.bigint "aicoo_lab_experiment_id", null: false
    t.integer "assumed_price_yen"
    t.text "body"
    t.datetime "created_at", null: false
    t.string "cta_text"
    t.datetime "generated_at"
    t.string "generation_source", default: "manual", null: false
    t.string "headline"
    t.text "notes"
    t.string "preview_slug", null: false
    t.datetime "published_at"
    t.string "published_slug"
    t.string "status", default: "draft", null: false
    t.string "subheadline"
    t.datetime "updated_at", null: false
    t.index ["aicoo_lab_experiment_id"], name: "index_aicoo_lab_landing_pages_on_aicoo_lab_experiment_id"
    t.index ["aicoo_lab_experiment_id"], name: "index_lab_landing_pages_on_experiment_id", unique: true
    t.index ["generation_source"], name: "index_aicoo_lab_landing_pages_on_generation_source"
    t.index ["preview_slug"], name: "index_aicoo_lab_landing_pages_on_preview_slug", unique: true
    t.index ["published_slug"], name: "index_aicoo_lab_landing_pages_on_published_slug", unique: true
    t.index ["status"], name: "index_aicoo_lab_landing_pages_on_status"
  end

  create_table "aicoo_lab_predictions", force: :cascade do |t|
    t.bigint "aicoo_lab_experiment_id", null: false
    t.decimal "confidence"
    t.datetime "created_at", null: false
    t.datetime "predicted_at", null: false
    t.decimal "predicted_value", null: false
    t.string "predicted_value_unit", null: false
    t.string "prediction_source", default: "lab", null: false
    t.string "prediction_type", null: false
    t.text "rationale"
    t.integer "target_days", null: false
    t.datetime "updated_at", null: false
    t.index ["aicoo_lab_experiment_id", "prediction_type", "target_days"], name: "index_lab_predictions_on_experiment_type_days"
    t.index ["aicoo_lab_experiment_id"], name: "index_aicoo_lab_predictions_on_aicoo_lab_experiment_id"
    t.index ["prediction_source"], name: "index_aicoo_lab_predictions_on_prediction_source"
  end

  create_table "aicoo_lab_results", force: :cascade do |t|
    t.decimal "actual_value", null: false
    t.string "actual_value_unit", null: false
    t.bigint "aicoo_lab_experiment_id", null: false
    t.datetime "created_at", null: false
    t.boolean "is_formal_score", default: false, null: false
    t.datetime "measured_at", null: false
    t.string "result_type", null: false
    t.integer "sample_size"
    t.boolean "sample_threshold_reached", default: false, null: false
    t.integer "target_days", null: false
    t.datetime "updated_at", null: false
    t.index ["aicoo_lab_experiment_id", "result_type", "target_days"], name: "index_lab_results_on_experiment_type_days"
    t.index ["aicoo_lab_experiment_id"], name: "index_aicoo_lab_results_on_aicoo_lab_experiment_id"
    t.index ["is_formal_score"], name: "index_aicoo_lab_results_on_is_formal_score"
    t.index ["sample_threshold_reached"], name: "index_aicoo_lab_results_on_sample_threshold_reached"
  end

  create_table "aicoo_lab_settings", force: :cascade do |t|
    t.boolean "auto_generate_enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.boolean "free_experiments_continue_after_budget", default: true, null: false
    t.integer "hourly_cost_yen", default: 1226, null: false
    t.integer "minimum_sample_pv", default: 1000, null: false
    t.integer "monthly_budget_yen", default: 5000, null: false
    t.datetime "updated_at", null: false
  end

  create_table "aicoo_lab_signups", force: :cascade do |t|
    t.bigint "aicoo_lab_landing_page_id", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "ip_hash"
    t.text "note"
    t.text "referrer"
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["aicoo_lab_landing_page_id"], name: "index_aicoo_lab_signups_on_aicoo_lab_landing_page_id"
    t.index ["email"], name: "index_aicoo_lab_signups_on_email"
  end

  create_table "aicoo_revenue_executions", force: :cascade do |t|
    t.integer "actual_90d_profit_yen"
    t.integer "budget_yen"
    t.decimal "calibration_score"
    t.datetime "created_at", null: false
    t.datetime "done_at"
    t.decimal "error_rate"
    t.integer "estimated_work_minutes"
    t.integer "expected_90d_profit_yen"
    t.datetime "measured_at"
    t.integer "neglect_loss_90d_yen", default: 0, null: false
    t.text "note"
    t.datetime "planned_at"
    t.string "prediction_source", default: "revenue", null: false
    t.text "result_note"
    t.decimal "revenue_score"
    t.integer "revenue_total_value_yen"
    t.datetime "skipped_at"
    t.integer "source_id", null: false
    t.string "source_type", null: false
    t.string "status", default: "planned", null: false
    t.decimal "success_probability"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["measured_at"], name: "index_aicoo_revenue_executions_on_measured_at"
    t.index ["planned_at"], name: "index_aicoo_revenue_executions_on_planned_at"
    t.index ["prediction_source"], name: "index_aicoo_revenue_executions_on_prediction_source"
    t.index ["source_type", "source_id"], name: "index_aicoo_revenue_executions_on_source_type_and_source_id"
    t.index ["status"], name: "index_aicoo_revenue_executions_on_status"
  end

  create_table "aicoo_settings", force: :cascade do |t|
    t.boolean "auto_queue_data_preparation_tasks", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "analytics_fetch_runs", force: :cascade do |t|
    t.bigint "analytics_source_setting_id", null: false
    t.datetime "created_at", null: false
    t.integer "data_import_id"
    t.text "error_message"
    t.datetime "finished_at"
    t.integer "snapshot_count", default: 0, null: false
    t.string "source_type", null: false
    t.datetime "started_at"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.integer "updated_neglect_loss_count", default: 0, null: false
    t.index ["analytics_source_setting_id"], name: "index_analytics_fetch_runs_on_analytics_source_setting_id"
    t.index ["source_type"], name: "index_analytics_fetch_runs_on_source_type"
    t.index ["status"], name: "index_analytics_fetch_runs_on_status"
  end

  create_table "analytics_source_settings", force: :cascade do |t|
    t.bigint "aicoo_analytics_site_id"
    t.string "authentication_mode", default: "shared", null: false
    t.text "client_id"
    t.text "client_secret"
    t.datetime "created_at", null: false
    t.text "credentials_json"
    t.boolean "enabled", default: true, null: false
    t.integer "fetch_days", default: 28, null: false
    t.bigint "google_credential_id"
    t.datetime "last_fetched_at"
    t.string "name", null: false
    t.datetime "oauth_connected_at"
    t.string "property_id"
    t.text "refresh_token"
    t.string "site_url"
    t.string "source_type", null: false
    t.datetime "updated_at", null: false
    t.index ["aicoo_analytics_site_id"], name: "index_analytics_source_settings_on_aicoo_analytics_site_id"
    t.index ["authentication_mode"], name: "index_analytics_source_settings_on_authentication_mode"
    t.index ["google_credential_id"], name: "index_analytics_source_settings_on_google_credential_id"
    t.index ["source_type"], name: "index_analytics_source_settings_on_source_type"
  end

  create_table "auto_revision_tasks", force: :cascade do |t|
    t.bigint "action_candidate_id", null: false
    t.datetime "approved_at"
    t.bigint "business_id", null: false
    t.text "changed_files"
    t.text "codex_output"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.text "execution_prompt"
    t.datetime "finished_at"
    t.string "generated_by", default: "aicoo", null: false
    t.jsonb "metadata", default: {}, null: false
    t.decimal "priority_score", precision: 12, scale: 2, default: "0.0", null: false
    t.text "result_summary"
    t.string "risk_level", default: "medium", null: false
    t.datetime "started_at"
    t.string "status", default: "draft", null: false
    t.text "test_result"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["action_candidate_id"], name: "index_auto_revision_tasks_on_action_candidate_id"
    t.index ["business_id"], name: "index_auto_revision_tasks_on_business_id"
    t.index ["generated_by"], name: "index_auto_revision_tasks_on_generated_by"
    t.index ["priority_score"], name: "index_auto_revision_tasks_on_priority_score"
    t.index ["risk_level"], name: "index_auto_revision_tasks_on_risk_level"
    t.index ["status"], name: "index_auto_revision_tasks_on_status"
  end

  create_table "business_metric_dailies", force: :cascade do |t|
    t.integer "affiliate_clicks", default: 0, null: false
    t.bigint "business_id", null: false
    t.integer "clicks", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "impressions", default: 0, null: false
    t.integer "map_clicks", default: 0, null: false
    t.integer "pageviews", default: 0, null: false
    t.integer "phone_clicks", default: 0, null: false
    t.date "recorded_on", null: false
    t.integer "sessions", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "recorded_on"], name: "index_business_metric_dailies_on_business_id_and_recorded_on", unique: true
    t.index ["business_id"], name: "index_business_metric_dailies_on_business_id"
    t.index ["recorded_on"], name: "index_business_metric_dailies_on_recorded_on"
  end

  create_table "businesses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "gsc_site_url"
    t.string "name"
    t.string "status"
    t.datetime "updated_at", null: false
  end

  create_table "data_imports", force: :cascade do |t|
    t.bigint "aicoo_analytics_site_id"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.bigint "data_source_id", null: false
    t.string "filename", null: false
    t.datetime "imported_at", null: false
    t.text "processed_text"
    t.text "raw_text"
    t.integer "row_count"
    t.datetime "updated_at", null: false
    t.index ["aicoo_analytics_site_id"], name: "index_data_imports_on_aicoo_analytics_site_id"
    t.index ["data_source_id"], name: "index_data_imports_on_data_source_id"
  end

  create_table "data_sources", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "notes"
    t.string "source_type", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_data_sources_on_business_id"
  end

  create_table "meta_evaluation_snapshots", force: :cascade do |t|
    t.bigint "aicoo_daily_run_id"
    t.decimal "average_confidence_score", default: "0.0", null: false
    t.integer "average_expected_value_yen", default: 0, null: false
    t.bigint "business_id"
    t.integer "candidate_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "evaluator_type", null: false
    t.text "note"
    t.date "recorded_on", null: false
    t.datetime "updated_at", null: false
    t.decimal "weighted_contribution_score", default: "0.0", null: false
    t.index ["aicoo_daily_run_id"], name: "index_meta_evaluation_snapshots_on_aicoo_daily_run_id"
    t.index ["business_id"], name: "index_meta_evaluation_snapshots_on_business_id"
    t.index ["recorded_on", "business_id", "evaluator_type"], name: "idx_meta_eval_snapshots_unique_date_business_type", unique: true
    t.index ["recorded_on", "evaluator_type"], name: "idx_meta_eval_snapshots_unique_global_type", unique: true, where: "(business_id IS NULL)"
  end

  create_table "owner_task_completion_logs", force: :cascade do |t|
    t.string "action_label", null: false
    t.string "action_result", null: false
    t.datetime "completed_at", null: false
    t.datetime "created_at", null: false
    t.text "message"
    t.jsonb "metadata", default: {}, null: false
    t.integer "target_id"
    t.string "target_type"
    t.string "task_type", null: false
    t.datetime "updated_at", null: false
    t.index ["action_result"], name: "index_owner_task_completion_logs_on_action_result"
    t.index ["completed_at"], name: "index_owner_task_completion_logs_on_completed_at"
    t.index ["target_type", "target_id"], name: "index_owner_task_completion_logs_on_target_type_and_target_id"
    t.index ["task_type"], name: "index_owner_task_completion_logs_on_task_type"
  end

  create_table "proxy_score_weight_adjustment_logs", force: :cascade do |t|
    t.datetime "adjusted_at", null: false
    t.decimal "adjustment_rate", precision: 10, scale: 6, default: "0.0", null: false
    t.jsonb "after_weights", default: {}, null: false
    t.jsonb "before_weights", default: {}, null: false
    t.bigint "business_id"
    t.integer "confidence_score", default: 0, null: false
    t.datetime "created_at", null: false
    t.date "end_date", null: false
    t.bigint "proxy_score_weight_id", null: false
    t.text "reason", null: false
    t.integer "revenue_events_count", default: 0, null: false
    t.integer "sample_days_count", default: 0, null: false
    t.date "start_date", null: false
    t.datetime "updated_at", null: false
    t.index ["adjusted_at"], name: "index_proxy_score_weight_adjustment_logs_on_adjusted_at"
    t.index ["business_id", "adjusted_at"], name: "index_proxy_weight_logs_on_business_and_adjusted_at"
    t.index ["business_id"], name: "index_proxy_score_weight_adjustment_logs_on_business_id"
    t.index ["proxy_score_weight_id"], name: "idx_on_proxy_score_weight_id_bd8b219702"
  end

  create_table "proxy_score_weights", force: :cascade do |t|
    t.datetime "adjusted_at"
    t.decimal "affiliate_clicks_weight", precision: 16, scale: 8, default: "20.0", null: false
    t.bigint "business_id"
    t.decimal "clicks_weight", precision: 16, scale: 8, default: "1.0", null: false
    t.integer "confidence_score", default: 0, null: false
    t.datetime "created_at", null: false
    t.decimal "impressions_weight", precision: 16, scale: 8, default: "0.01", null: false
    t.decimal "map_clicks_weight", precision: 16, scale: 8, default: "8.0", null: false
    t.text "note"
    t.decimal "pageviews_weight", precision: 16, scale: 8, default: "0.5", null: false
    t.decimal "phone_clicks_weight", precision: 16, scale: 8, default: "10.0", null: false
    t.decimal "sessions_weight", precision: 16, scale: 8, default: "1.0", null: false
    t.string "source_type", default: "default", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_proxy_score_weights_on_business_id"
    t.index ["source_type"], name: "index_proxy_score_weights_on_source_type"
  end

  create_table "revenue_events", force: :cascade do |t|
    t.bigint "action_candidate_id"
    t.bigint "action_execution_log_id"
    t.bigint "action_result_id"
    t.integer "amount", null: false
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.date "occurred_on", null: false
    t.datetime "updated_at", null: false
    t.index ["action_candidate_id"], name: "index_revenue_events_on_action_candidate_id"
    t.index ["action_execution_log_id"], name: "index_revenue_events_on_action_execution_log_id"
    t.index ["action_result_id"], name: "index_revenue_events_on_action_result_id"
    t.index ["business_id"], name: "index_revenue_events_on_business_id"
    t.index ["event_type"], name: "index_revenue_events_on_event_type"
    t.index ["occurred_on"], name: "index_revenue_events_on_occurred_on"
  end

  create_table "serp_analyses", force: :cascade do |t|
    t.datetime "analyzed_at", null: false
    t.bigint "business_id", null: false
    t.integer "competition_score"
    t.datetime "created_at", null: false
    t.bigint "data_import_id"
    t.string "device"
    t.string "keyword", null: false
    t.string "location"
    t.integer "result_count"
    t.string "search_engine", default: "google", null: false
    t.text "summary"
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_serp_analyses_on_business_id"
    t.index ["data_import_id"], name: "index_serp_analyses_on_data_import_id"
  end

  create_table "serp_results", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", null: false
    t.bigint "serp_analysis_id", null: false
    t.text "snippet"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["serp_analysis_id"], name: "index_serp_results_on_serp_analysis_id"
  end

  add_foreign_key "action_candidate_score_snapshots", "action_candidates"
  add_foreign_key "action_candidate_score_snapshots", "businesses"
  add_foreign_key "action_candidates", "businesses"
  add_foreign_key "action_execution_logs", "action_candidates"
  add_foreign_key "action_execution_logs", "action_results"
  add_foreign_key "action_execution_logs", "businesses"
  add_foreign_key "action_execution_logs", "revenue_events"
  add_foreign_key "action_prediction_calibration_logs", "aicoo_daily_runs"
  add_foreign_key "action_results", "action_candidates"
  add_foreign_key "action_results", "businesses"
  add_foreign_key "ai_evaluation_runs", "businesses"
  add_foreign_key "aicoo_analytics_sites", "businesses"
  add_foreign_key "aicoo_lab_ai_drafts", "aicoo_lab_generation_runs", column: "generation_run_id"
  add_foreign_key "aicoo_lab_error_metrics", "aicoo_lab_experiments"
  add_foreign_key "aicoo_lab_error_metrics", "aicoo_lab_predictions"
  add_foreign_key "aicoo_lab_error_metrics", "aicoo_lab_results"
  add_foreign_key "aicoo_lab_experiment_candidates", "aicoo_lab_experiments", column: "converted_experiment_id"
  add_foreign_key "aicoo_lab_landing_page_events", "aicoo_lab_landing_pages"
  add_foreign_key "aicoo_lab_landing_pages", "aicoo_lab_experiments"
  add_foreign_key "aicoo_lab_predictions", "aicoo_lab_experiments"
  add_foreign_key "aicoo_lab_results", "aicoo_lab_experiments"
  add_foreign_key "aicoo_lab_signups", "aicoo_lab_landing_pages"
  add_foreign_key "analytics_fetch_runs", "analytics_source_settings"
  add_foreign_key "analytics_source_settings", "aicoo_analytics_sites"
  add_foreign_key "analytics_source_settings", "aicoo_google_credentials", column: "google_credential_id"
  add_foreign_key "auto_revision_tasks", "action_candidates"
  add_foreign_key "auto_revision_tasks", "businesses"
  add_foreign_key "business_metric_dailies", "businesses"
  add_foreign_key "data_imports", "aicoo_analytics_sites"
  add_foreign_key "data_imports", "data_sources"
  add_foreign_key "data_sources", "businesses"
  add_foreign_key "meta_evaluation_snapshots", "aicoo_daily_runs"
  add_foreign_key "meta_evaluation_snapshots", "businesses"
  add_foreign_key "proxy_score_weight_adjustment_logs", "businesses"
  add_foreign_key "proxy_score_weight_adjustment_logs", "proxy_score_weights"
  add_foreign_key "proxy_score_weights", "businesses"
  add_foreign_key "revenue_events", "action_candidates"
  add_foreign_key "revenue_events", "action_execution_logs"
  add_foreign_key "revenue_events", "action_results"
  add_foreign_key "revenue_events", "businesses"
  add_foreign_key "serp_analyses", "businesses"
  add_foreign_key "serp_analyses", "data_imports"
  add_foreign_key "serp_results", "serp_analyses"
end
