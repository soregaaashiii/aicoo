module Admin
  class SerpSettingsController < ApplicationController
    def show
      load_settings
    end

    def update
      load_settings
      @serp_profile.update!(
        enabled: ActiveModel::Type::Boolean.new.cast(serp_settings_params.fetch(:enabled, @serp_profile.enabled)),
        monthly_budget_yen: serp_settings_params[:monthly_budget_yen].to_i,
        monthly_spend_yen: serp_settings_params[:monthly_spend_yen].to_i,
        metadata: @serp_profile.metadata.to_h.merge(
          Aicoo::Serp::ScanPlan::METADATA_UNIT_COST_KEY => serp_settings_params[:unit_result_cost_yen].presence || Aicoo::Serp::ScanPlan::DEFAULT_UNIT_RESULT_COST_YEN,
          Aicoo::Serp::ScanPlan::METADATA_LIMIT_KEY => serp_settings_params[:serp_scan_limit].presence || Aicoo::Serp::ScanPlan::DEFAULT_LIMIT
        )
      )
      redirect_to admin_serp_settings_path, notice: "新規事業探索の予算設定を保存しました。"
    rescue ActiveRecord::RecordInvalid => e
      load_settings
      flash.now[:alert] = "新規事業探索の予算設定を保存できませんでした: #{e.record.errors.full_messages.to_sentence}"
      render :show, status: :unprocessable_entity
    end

    def update_scheduler
      Aicoo::Serp::Scheduler.update!(exploration_settings_params)
      redirect_to admin_serp_settings_path(anchor: "serp-settings"), notice: "新規事業探索設定を保存しました。"
    end

    def run_now
      Aicoo::Serp::Scheduler.update!(exploration_settings_params) if params[:serp_exploration].present?

      settings = Aicoo::Serp::Scheduler.settings
      serp_run = Aicoo::Serp::RunExecutor.new(
        executed_by: "manual",
        force: ActiveModel::Type::Boolean.new.cast(params[:force]),
        exploration_mode: settings["exploration_mode"],
        exploration_query: settings["exploration_query"],
        exploration_region: settings["exploration_region"],
        learning_enabled: settings["learning_enabled"],
        new_field_ratio: settings["new_field_ratio"],
        proven_field_ratio: settings["proven_field_ratio"]
      ).call

      redirect_to admin_serp_settings_path(serp_run_id: serp_run.id),
                  notice: "新規事業探索が完了しました。取得 #{serp_run.query_count}件 / 新規事業候補 #{serp_run.candidate_count}件"
    rescue StandardError => e
      redirect_to admin_serp_settings_path, alert: "新規事業探索に失敗しました: #{e.message}"
    end

    private

    def load_settings
      @provider_keys = Aicoo::Serp::ProviderRegistry.provider_keys
      @current_provider = (ENV["AICOO_SERP_PROVIDER"].presence || "serper").to_s
      @serp_profile = DataSourceCostProfile.for_source("serp")
      @serp_optional_mode = Aicoo::Serp::OptionalMode.call
      @serp_settings = Aicoo::Serp::Scheduler.settings
      @current_serp_run = SerpRun.find_by(id: params[:serp_run_id]) || SerpRun.recent.first
      @api_key_configured = @serp_optional_mode.api_key_configured
      @current_run_candidates = current_run_candidates
      @serp_businessized_businesses = serp_businessized_businesses
    end

    def current_run_candidates
      return ActionCandidate.none unless @current_serp_run

      ActionCandidate
        .includes(:business)
        .where("metadata ->> 'serp_run_id' = ?", @current_serp_run.id.to_s)
        .where(department: "new_business", generation_source: "serp")
        .order(Arel.sql("final_score DESC NULLS LAST, expected_hourly_value_yen DESC NULLS LAST, created_at DESC"))
    end

    def serp_businessized_businesses
      Business
        .real_businesses
        .where("source = :source OR metadata ->> 'auto_serp_business' = :true_value OR metadata ->> 'generation_source' = :source",
               source: "serp",
               true_value: "true")
        .order(created_at: :desc)
        .limit(20)
    end

    def serp_settings_params
      params.fetch(:serp_settings, {}).permit(:monthly_budget_yen, :monthly_spend_yen, :unit_result_cost_yen, :serp_scan_limit, :enabled)
    end

    def exploration_settings_params
      raw = params.fetch(:serp_exploration, {}).permit(
        :mode,
        :query,
        :country,
        :region,
        :daily_query_limit,
        :learning_enabled,
        :new_field_ratio,
        :proven_field_ratio,
        exclusion_rules: []
      )

      {
        "scheduler_enabled" => @serp_settings&.fetch("scheduler_enabled", false) || Aicoo::Serp::Scheduler.settings["scheduler_enabled"],
        "frequency" => "daily",
        "run_time" => Aicoo::Serp::Scheduler.settings["run_time"],
        "daily_query_limit" => raw[:daily_query_limit].to_i.positive? ? raw[:daily_query_limit].to_i : Aicoo::Serp::Scheduler.settings["daily_query_limit"],
        "max_concurrency" => 1,
        "exploration_mode" => raw[:mode].presence_in(%w[ai_auto industry keyword]) || Aicoo::Serp::Scheduler.settings["exploration_mode"],
        "exploration_query" => raw[:query].to_s.strip,
        "exploration_country" => raw[:country].presence || "日本",
        "exploration_region" => raw[:region].to_s.strip,
        "learning_enabled" => ActiveModel::Type::Boolean.new.cast(raw[:learning_enabled]),
        "new_field_ratio" => ratio_value(raw[:new_field_ratio], Aicoo::Serp::Scheduler.settings["new_field_ratio"]),
        "proven_field_ratio" => ratio_value(raw[:proven_field_ratio], Aicoo::Serp::Scheduler.settings["proven_field_ratio"]),
        "exclusion_rules" => Array(raw[:exclusion_rules]).presence || %w[existing_businesses deleted_businesses duplicate_markets]
      }
    end

    def ratio_value(value, fallback)
      parsed = Integer(value, exception: false)
      return fallback if parsed.nil?

      parsed.clamp(0, 100)
    end
  end
end
