module Admin
  class SerpQueriesController < ApplicationController
    before_action :set_serp_query, only: %i[edit update destroy toggle pause resume archive run_now]

    def index
      @businesses = Business.real_businesses.order(:name)
      @business_id = params[:business_id].presence
      @category = params[:category].presence_in(SerpQuery::CATEGORIES)
      @status = params[:status].presence_in(SerpQuery::STATUSES)
      @enabled = params[:enabled].presence
      @q = params[:q].to_s.strip
      @serp_query = SerpQuery.new(business_id: @business_id, category: "existing_business", status: "active", enabled: true, priority: 100, country: "jp", language: "ja", daily_limit: 1)
      @serp_queries = filtered_scope.includes(:business).order(:priority, :query).limit(200)
    end

    def create
      attrs = serp_query_params.to_h
      business = Business.real_businesses.find(attrs.fetch("business_id"))
      queries = SerpQuery.parse_queries(attrs["query"])
      return redirect_to create_failure_location(attrs), alert: "SERP検索クエリを入力してください。" if queries.empty?

      added = []
      existing = []
      invalid = []
      queries.each do |query_text|
        normalized_query = SerpQuery.normalize(query_text)
        serp_query = business.serp_queries.find_or_initialize_by(normalized_query:)
        if serp_query.persisted?
          existing << serp_query
          next
        end

        serp_query.assign_attributes(attrs.except("business_id", "query").merge("query" => query_text))
        if serp_query.save
          added << serp_query
        else
          invalid << [ query_text, serp_query.errors.full_messages.to_sentence ]
        end
      end

      if invalid.any? && added.empty?
        redirect_to create_failure_location(attrs),
                    alert: "SERP検索クエリを追加できません: #{invalid.map { |query, error| "#{query}: #{error}" }.join(' / ')}"
      else
        parts = []
        parts << "追加 #{added.size}件" if added.any?
        parts << "既存 #{existing.size}件" if existing.any?
        parts << "無効 #{invalid.size}件" if invalid.any?
        redirect_to create_success_location(business, added.first || existing.first),
                    notice: "SERP検索クエリを#{added.size}件追加しました。#{parts.join(' / ')}。追加しただけでは検索は実行されません。"
      end
    end

    def edit
      @businesses = Business.real_businesses.order(:name)
    end

    def update
      if @serp_query.update(serp_query_params)
        redirect_to admin_serp_queries_path(business_id: @serp_query.business_id, anchor: "serp-query-#{@serp_query.id}"), notice: "SERP検索クエリを更新しました。"
      else
        @businesses = Business.real_businesses.order(:name)
        render :edit, status: :unprocessable_entity
      end
    end

    def toggle
      @serp_query.toggle!
      redirect_back fallback_location: admin_serp_queries_path(business_id: @serp_query.business_id), notice: "#{@serp_query.query} を#{@serp_query.enabled? ? 'ON' : 'OFF'}にしました。"
    end

    def pause
      @serp_query.pause!
      redirect_back fallback_location: admin_serp_queries_path(business_id: @serp_query.business_id), notice: "#{@serp_query.query} をPauseしました。"
    end

    def resume
      @serp_query.resume!
      redirect_back fallback_location: admin_serp_queries_path(business_id: @serp_query.business_id), notice: "#{@serp_query.query} を再開しました。"
    end

    def archive
      @serp_query.archive!
      redirect_back fallback_location: admin_serp_queries_path(business_id: @serp_query.business_id), notice: "#{@serp_query.query} をArchiveしました。"
    end

    def run_now
      serp_run = Aicoo::Serp::RunExecutor.new(executed_by: "manual", force: true, serp_query: @serp_query).call
      redirect_to admin_serp_run_path(serp_run),
                  notice: "#{@serp_query.query} を今すぐ実行しました。status=#{serp_run.status}"
    rescue StandardError => e
      redirect_back fallback_location: admin_serp_queries_path(business_id: @serp_query.business_id),
                    alert: "#{@serp_query.query} のSERP実行に失敗しました: #{e.message}"
    end

    def destroy
      business_id = @serp_query.business_id
      @serp_query.destroy!
      redirect_to admin_serp_queries_path(business_id:), notice: "SERP検索クエリを削除しました。"
    end

    private

    def filtered_scope
      scope = SerpQuery.all
      scope = scope.where(business_id: @business_id) if @business_id.present?
      scope = scope.where(category: @category) if @category.present?
      scope = scope.where(status: @status) if @status.present?
      scope = scope.where(enabled: ActiveModel::Type::Boolean.new.cast(@enabled)) if @enabled.in?(%w[true false])
      scope = scope.where("query ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%") if @q.present?
      scope
    end

    def set_serp_query
      @serp_query = SerpQuery.find(params[:id])
    end

    def serp_query_params
      params.expect(
        serp_query: [
          :business_id,
          :query,
          :category,
          :status,
          :enabled,
          :priority,
          :country,
          :language,
          :daily_limit
        ]
      )
    end

    def create_success_location(business, serp_query)
      return params[:return_to] if params[:return_to].present?

      admin_serp_queries_path(business_id: business.id, anchor: "serp-query-#{serp_query&.id}")
    end

    def create_failure_location(attrs)
      params[:return_to].presence || admin_serp_queries_path(business_id: attrs["business_id"])
    end
  end
end
