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
      redirect_to admin_serp_settings_path, notice: "SERP予算設定を保存しました。"
    rescue ActiveRecord::RecordInvalid => e
      load_settings
      flash.now[:alert] = "SERP予算設定を保存できませんでした: #{e.record.errors.full_messages.to_sentence}"
      render :show, status: :unprocessable_entity
    end

    def update_scheduler
      Aicoo::Serp::Scheduler.update!(
        "scheduler_enabled" => ActiveModel::Type::Boolean.new.cast(params.dig(:serp_scheduler, :scheduler_enabled)),
        "frequency" => params.dig(:serp_scheduler, :frequency).presence_in(%w[daily weekly monthly]) || "daily",
        "run_time" => params.dig(:serp_scheduler, :run_time).presence || "07:00",
        "daily_query_limit" => params.dig(:serp_scheduler, :daily_query_limit).to_i,
        "max_concurrency" => params.dig(:serp_scheduler, :max_concurrency).to_i
      )
      redirect_to admin_serp_settings_path(anchor: "serp-global"), notice: "SERP Scheduler設定を保存しました。"
    end

    def run_now
      result = Aicoo::Serp::Scheduler.run!(executed_by: "manual", force: ActiveModel::Type::Boolean.new.cast(params[:force]))
      if result.serp_run
        redirect_to admin_serp_settings_path(anchor: "serp-execution"),
                    notice: "SERP Runを実行しました。status=#{result.serp_run.status} query=#{result.serp_run.query_count}"
      else
        redirect_to admin_serp_settings_path(anchor: "serp-execution"),
                    alert: "SERP Runは実行されませんでした: #{result.reason}"
      end
    rescue StandardError => e
      redirect_to admin_serp_settings_path(anchor: "serp-execution"), alert: "SERP Runに失敗しました: #{e.message}"
    end

    def test_search
      load_settings
      @test_params = test_search_params.to_h.symbolize_keys
      @result = Aicoo::Serp::Adapter.call(
        provider: @test_params[:provider].presence&.to_sym,
        type: @test_params[:type].presence&.to_sym || :google_search,
        query: @test_params[:query],
        location: @test_params[:location].presence || "Japan",
        language: @test_params[:language].presence || "ja",
        limit: @test_params[:limit].presence || 10
      )
      flash.now[:notice] = "SERPテスト検索が完了しました。"
      render :show, status: :ok
    rescue Aicoo::Serp::MissingApiKeyError,
           Aicoo::Serp::UnsupportedProviderError,
           Aicoo::Serp::UnsupportedSearchTypeError,
           Aicoo::Serp::HttpError,
           Aicoo::Serp::RateLimitError,
           Aicoo::Serp::TimeoutError,
           Aicoo::Serp::ParseError => e
      load_settings
      @test_params ||= test_search_params.to_h.symbolize_keys
      @error_message = e.message
      flash.now[:alert] = e.message
      render :show, status: :unprocessable_entity
    end

    def update_business
      business = find_business
      business.update!(serp_enabled: ActiveModel::Type::Boolean.new.cast(params.dig(:serp_business, :serp_enabled)))
      redirect_to admin_serp_settings_path(anchor: business_anchor(business)), notice: "#{business.name}のSERP設定を保存しました。"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_serp_settings_path, alert: "SERP設定を保存できませんでした: #{e.record.errors.full_messages.to_sentence}"
    end

    def add_keywords
      business = find_business
      result = Aicoo::Serp::KeywordManager.add_manual_keywords!(
        business:,
        raw_keywords: params.dig(:serp_keywords, :keywords)
      )
      messages = []
      messages << "追加 #{result.added.size}件" if result.added.any?
      messages << "既存 #{result.existing.size}件" if result.existing.any?
      messages << "除外済み #{result.excluded.size}件" if result.excluded.any?
      messages << "無効 #{result.invalid.size}件" if result.invalid.any?
      flash_type = result.excluded.any? || result.invalid.any? ? :alert : :notice
      redirect_to admin_serp_settings_path(anchor: business_anchor(business)), flash: { flash_type => "キーワード処理: #{messages.presence&.join(' / ') || '変更なし'}" }
    end

    def regenerate_suggestions
      business = find_business
      suggestions = Aicoo::Serp::KeywordManager.generate_suggestions!(business:)
      redirect_to admin_serp_settings_path(anchor: business_anchor(business)), notice: "#{business.name}のキーワード候補を#{suggestions.size}件生成しました。"
    end

    def scan_business
      business = find_business
      result = Aicoo::Serp::ScanRunner.new(target_businesses: [ business ]).call
      if result.failed_count.positive?
        redirect_to admin_serp_settings_path(anchor: business_anchor(business)),
                    alert: "#{business.name}のSERP取得で失敗があります。成功 #{result.success_count}件 / 失敗 #{result.failed_count}件"
      else
        redirect_to admin_serp_settings_path(anchor: business_anchor(business)),
                    notice: "#{business.name}のSERP取得が完了しました。#{result.query_count}キーワード / #{result.result_count}件"
      end
    rescue StandardError => e
      redirect_to admin_serp_settings_path(anchor: business_anchor(business)), alert: "#{business.name}のSERP取得に失敗しました: #{e.message}"
    end

    def update_keyword
      keyword = find_keyword
      keyword.update!(
        keyword: keyword_params[:keyword].presence || keyword.keyword,
        priority_score: keyword_params[:priority_score],
        metadata_json: keyword.metadata_json.to_h.merge("manual_priority" => true)
      )
      redirect_to admin_serp_settings_path(anchor: business_anchor(keyword.business)), notice: "#{keyword.keyword} の優先度を保存しました。"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_serp_settings_path, alert: "キーワードを保存できませんでした: #{e.record.errors.full_messages.to_sentence}"
    end

    def approve_pending_keywords
      business = find_business
      updated_count = business.business_serp_keywords.pending.update_all(status: "active", updated_at: Time.current)
      redirect_to admin_serp_settings_path(anchor: "serp-keywords"),
                  notice: "#{business.name}の承認待ちキーワードを#{updated_count}件Activeにしました。"
    end

    def approve_keyword
      keyword = find_keyword
      keyword.activate!
      redirect_to admin_serp_settings_path(anchor: business_anchor(keyword.business)), notice: "#{keyword.keyword} を承認しました。"
    end

    def exclude_keyword
      keyword = find_keyword
      keyword.exclude!(reason: params.dig(:serp_keyword, :reason))
      redirect_to admin_serp_settings_path(anchor: business_anchor(keyword.business)), notice: "#{keyword.keyword} を除外しました。"
    end

    def pause_keyword
      keyword = find_keyword
      keyword.pause!
      redirect_to admin_serp_settings_path(anchor: business_anchor(keyword.business)), notice: "#{keyword.keyword} を一時停止しました。"
    end

    def resume_keyword
      keyword = find_keyword
      keyword.activate!
      redirect_to admin_serp_settings_path(anchor: business_anchor(keyword.business)), notice: "#{keyword.keyword} を再開しました。"
    end

    def archive_keyword
      keyword = find_keyword
      keyword.archive!
      redirect_to admin_serp_settings_path(anchor: business_anchor(keyword.business)), notice: "#{keyword.keyword} をアーカイブしました。"
    end

    def restore_keyword
      keyword = find_keyword
      keyword.restore!
      redirect_to admin_serp_settings_path(anchor: business_anchor(keyword.business)), notice: "#{keyword.keyword} を復元しました。"
    end

    def destroy_keyword
      keyword = find_keyword
      business = keyword.business
      keyword.destroy!
      redirect_to admin_serp_settings_path(anchor: business_anchor(business)), notice: "#{keyword.keyword} を削除しました。"
    end

    private

    def load_settings
      @provider_keys = Aicoo::Serp::ProviderRegistry.provider_keys
      @current_provider = (ENV["AICOO_SERP_PROVIDER"].presence || "serper").to_s
      @serp_profile = DataSourceCostProfile.for_source("serp")
      @serp_optional_mode = Aicoo::Serp::OptionalMode.call
      @serp_summary = Aicoo::Serp::Summary.call
      @serp_scheduler_settings = Aicoo::Serp::Scheduler.settings
      @latest_serp_run = SerpRun.recent.first
      @recent_serp_runs = SerpRun.recent.limit(10)
      @api_key_configured = @serp_optional_mode.api_key_configured
      @selected_period = params[:period].presence_in(%w[today yesterday seven_days]) || "today"
      @recent_serp_analyses = SerpAnalysis.includes(:business, :serp_results).order(analyzed_at: :desc, created_at: :desc).limit(30)
      @last_serp_error = SerpAnalysis.failed.order(updated_at: :desc).first
      @serp_analysis_count = SerpAnalysis.count
      @serp_result_count = SerpResult.count
      @today_serp_analysis_count = SerpAnalysis.where(analyzed_at: Time.zone.today.all_day).count
      @latest_daily_run_serp_steps = AicooDailyRunStep
        .includes(:aicoo_daily_run)
        .where(step_name: Aicoo::Serp::OptionalMode::SERP_DEPENDENT_STEPS)
        .order(created_at: :desc)
        .limit(12)
      @serp_businesses = Business.real_businesses
                                .includes(:business_serp_keywords, :business_data_source_settings, :serp_queries)
                                .order(:name)
      @selected_business = @serp_businesses.find { |business| business.id == params[:business_id].to_i } || @serp_businesses.first
      @serp_keyword_counts = BusinessSerpKeyword.where(business: @serp_businesses).group(:business_id, :status).count
      @serp_query_counts = SerpQuery.where(business: @serp_businesses).group(:business_id, :enabled).count
      @serp_latest_checked_at = BusinessSerpKeyword.where(business: @serp_businesses).group(:business_id).maximum(:last_checked_at)
      @serp_today_planned_counts = @serp_businesses.index_with do |business|
        Aicoo::Serp::ScanRunner.queries_for_business(business).size
      end
      @serp_latest_analysis_by_business_id = SerpAnalysis
        .where(business: @serp_businesses)
        .order(analyzed_at: :asc, created_at: :asc)
        .each_with_object({}) { |analysis, rows| rows[analysis.business_id] = analysis }
      @period_serp_analyses = SerpAnalysis.where(analyzed_at: selected_period_range)
      @business_period_serp_counts = @period_serp_analyses.group(:business_id).count
      @period_success_count = @period_serp_analyses.successful.count
      @period_failed_count = @period_serp_analyses.failed.count
      @period_running_count = @period_serp_analyses.running.count
      @period_skip_count = 0
      @period_error_messages = @period_serp_analyses.failed.limit(5).pluck(:keyword, :error_message)
      @business_period_success_counts = @period_serp_analyses.successful.group(:business_id).count
      @business_period_failed_counts = @period_serp_analyses.failed.group(:business_id).count
      @serp_candidate_counts_by_keyword = ActionCandidate
        .where(generation_source: "serp")
        .where(created_at: 30.days.ago..Time.current)
        .group("metadata ->> 'serp_keyword'")
        .count
      @test_params ||= {
        provider: @current_provider,
        type: "google_search",
        query: "大阪 喫煙 カフェ",
        location: "Japan",
        language: "ja",
        limit: 10
      }
    end

    def test_search_params
      params.fetch(:serp_test, {}).permit(:provider, :type, :query, :location, :language, :limit)
    end

    def serp_settings_params
      params.fetch(:serp_settings, {}).permit(:monthly_budget_yen, :monthly_spend_yen, :unit_result_cost_yen, :serp_scan_limit, :enabled)
    end

    def keyword_params
      params.fetch(:serp_keyword, {}).permit(:keyword, :priority_score)
    end

    def find_business
      Business.real_businesses.find(params[:business_id])
    end

    def find_keyword
      BusinessSerpKeyword.includes(:business).find(params[:id])
    end

    def business_anchor(business)
      "serp-business-#{business.id}"
    end

    def selected_period_range
      case @selected_period
      when "yesterday"
        Time.zone.yesterday.all_day
      when "seven_days"
        7.days.ago.beginning_of_day..Time.current
      else
        Time.zone.today.all_day
      end
    end
  end
end
