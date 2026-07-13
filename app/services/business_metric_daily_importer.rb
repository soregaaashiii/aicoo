class BusinessMetricDailyImporter
  Result = Data.define(:metric)
  Summary = Data.define(:processed_count, :created_count, :updated_count, :skipped_count, :failed_count) do
    def size = processed_count
    def any? = processed_count.to_i.positive?
  end
  Progress = Data.define(
    :event,
    :target_business_count,
    :processed_business_count,
    :current_business_id,
    :current_business_name,
    :created_count,
    :updated_count,
    :skipped_count,
    :error_count,
    :elapsed_seconds,
    :last_progress_at,
    :error_message
  )

  DATE_KEYS = %w[date recorded_on occurred_on event_date].freeze
  METRIC_FIELDS = %i[
    impressions
    clicks
    sessions
    pageviews
    phone_clicks
    map_clicks
    affiliate_clicks
    users
    views_per_user
    average_engagement_time_seconds
    engagement_rate
    bounce_rate
    conversions
    event_count
    scroll_events
    internal_search_events
    average_position
  ].freeze
  DECIMAL_FIELDS = %i[views_per_user engagement_rate bounce_rate average_position].freeze

  DEFAULT_PER_BUSINESS_TIMEOUT = 60.seconds
  DEFAULT_STEP_TIMEOUT = 10.minutes
  SNAPSHOT_LOOKAHEAD = 2.days

  def self.import_all!(date:, progress: nil, per_business_timeout: DEFAULT_PER_BUSINESS_TIMEOUT, step_timeout: DEFAULT_STEP_TIMEOUT)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    businesses = Business.real_businesses.order(:id)
    target_business_count = businesses.count
    processed_count = 0
    created_count = 0
    updated_count = 0
    skipped_count = 0
    error_count = 0

    emit_progress(
      progress,
      event: "start",
      target_business_count:,
      processed_business_count: 0,
      created_count:,
      updated_count:,
      skipped_count:,
      error_count:,
      started_at:
    )

    businesses.find_each.with_index do |business, index|
      if elapsed_seconds(started_at) >= step_timeout
        skipped_count += target_business_count - index
        emit_progress(
          progress,
          event: "step_timeout",
          target_business_count:,
          processed_business_count: index,
          current_business_id: business.id,
          current_business_name: business.name,
          created_count:,
          updated_count:,
          skipped_count:,
          error_count:,
          elapsed_seconds: elapsed_seconds(started_at),
          error_message: "business_metrics_import step timeout"
        )
        break
      end

      emit_progress(
        progress,
        event: "business_start",
        target_business_count:,
        processed_business_count: index,
        current_business_id: business.id,
        current_business_name: business.name,
        created_count:,
        updated_count:,
        skipped_count:,
        error_count:,
        started_at:
      )

      was_new = !BusinessMetricDaily.exists?(business:, recorded_on: date)
      import_one_with_timeout!(business:, date:, per_business_timeout:)
      processed_count += 1
      was_new ? created_count += 1 : updated_count += 1
      emit_progress(
        progress,
        event: "business_finish",
        target_business_count:,
        processed_business_count: index + 1,
        current_business_id: business.id,
        current_business_name: business.name,
        created_count:,
        updated_count:,
        skipped_count:,
        error_count:,
        started_at:
      )
    rescue StandardError => e
      error_count += 1
      emit_progress(
        progress,
        event: "business_error",
        target_business_count:,
        processed_business_count: index + 1,
        current_business_id: business.id,
        current_business_name: business.name,
        created_count:,
        updated_count:,
        skipped_count:,
        error_count:,
        started_at:,
        error_message: "#{e.class}: #{e.message}"
      )
    end

    emit_progress(
      progress,
      event: "finish",
      target_business_count:,
      processed_business_count: processed_count + error_count,
      created_count:,
      updated_count:,
      skipped_count:,
      error_count:,
      started_at:
    )

    Summary.new(
      processed_count:,
      created_count:,
      updated_count:,
      skipped_count:,
      failed_count: error_count
    )
  end

  def self.import_range!(business:, start_date:, end_date:)
    (start_date.to_date..end_date.to_date).map do |date|
      new(business:, date:).call
    end
  end

  def self.import_all_range!(start_date:, end_date:)
    processed_count = 0
    updated_count = 0
    error_count = 0

    Business.real_businesses.find_each do |business|
      results = import_range!(business:, start_date:, end_date:)
      processed_count += results.size
      updated_count += results.size
    rescue StandardError => e
      error_count += 1
      Rails.logger.warn("[BusinessMetricDailyImporter] range import failed business_id=#{business.id} #{e.class}: #{e.message}")
    end

    Summary.new(
      processed_count:,
      created_count: 0,
      updated_count:,
      skipped_count: 0,
      failed_count: error_count
    )
  end

  def initialize(business:, date: Date.yesterday)
    @business = business
    @date = date.to_date
  end

  def call
    values = empty_values
    merge_values!(values, gsc_values)
    merge_values!(values, ga4_values)
    merge_values!(values, lp_event_values)

    metric = BusinessMetricDaily.find_or_initialize_by(business:, recorded_on: date)
    metric.assign_attributes(values)
    metric.save!

    Result.new(metric:)
  end

  private

  attr_reader :business, :date

  def empty_values
    METRIC_FIELDS.index_with(0)
  end

  def merge_values!(target, source)
    source.each do |key, value|
      target[key] = if DECIMAL_FIELDS.include?(key)
        value.to_d
      else
        target[key].to_i + value.to_i
      end
    end
  end

  def gsc_values
    {
      impressions: snapshot_metric_total("gsc", "impressions"),
      clicks: snapshot_metric_total("gsc", "clicks"),
      average_position: snapshot_metric_average("gsc", "average_position", "position")
    }
  end

  def ga4_values
    {
      sessions: snapshot_metric_total("ga4", "sessions"),
      pageviews: snapshot_metric_total("ga4", "page_views", "pageviews", "screenPageViews", "views"),
      users: snapshot_metric_total("ga4", "users", "activeUsers", "totalUsers"),
      views_per_user: snapshot_metric_average("ga4", "viewsPerUser", "views_per_user"),
      average_engagement_time_seconds: snapshot_metric_average("ga4", "averageEngagementTime", "average_engagement_time_seconds").round,
      engagement_rate: snapshot_metric_average("ga4", "engagementRate", "engagement_rate"),
      bounce_rate: snapshot_metric_average("ga4", "bounceRate", "bounce_rate"),
      conversions: snapshot_metric_total("ga4", "conversions", "keyEvents"),
      event_count: snapshot_metric_total("ga4", "eventCount", "event_count"),
      scroll_events: snapshot_metric_total("ga4", "scroll", "scroll_events", "scrollEvents"),
      internal_search_events: snapshot_metric_total("ga4", "internal_search", "view_search_results", "internal_search_events")
    }
  end

  def lp_event_values
    # TODO: LPイベントをBusinessへ直接紐づける設計が入ったら、phone/map/affiliateクリックをここで集計する。
    {
      phone_clicks: snapshot_metric_total("landing_page", "phone_clicks"),
      map_clicks: snapshot_metric_total("landing_page", "map_clicks"),
      affiliate_clicks: snapshot_metric_total("landing_page", "affiliate_clicks")
    }
  end

  def self.import_one_with_timeout!(business:, date:, per_business_timeout:)
    ActiveRecord::Base.transaction do
      apply_statement_timeout!(per_business_timeout)
      new(business:, date:).call
    end
  end

  def self.apply_statement_timeout!(timeout)
    return unless ActiveRecord::Base.connection.adapter_name.downcase.include?("postgres")

    milliseconds = (timeout.to_f * 1000).to_i
    ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = #{milliseconds}")
  end

  def self.emit_progress(progress, started_at: nil, elapsed_seconds: nil, **attributes)
    return unless progress

    progress.call(
      Progress.new(
        event: attributes[:event],
        target_business_count: attributes[:target_business_count].to_i,
        processed_business_count: attributes[:processed_business_count].to_i,
        current_business_id: attributes[:current_business_id],
        current_business_name: attributes[:current_business_name],
        created_count: attributes[:created_count].to_i,
        updated_count: attributes[:updated_count].to_i,
        skipped_count: attributes[:skipped_count].to_i,
        error_count: attributes[:error_count].to_i,
        elapsed_seconds: elapsed_seconds || (started_at ? self.elapsed_seconds(started_at) : 0),
        last_progress_at: Time.current,
        error_message: attributes[:error_message]
      )
    )
  end

  def self.elapsed_seconds(started_at)
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  end

  def matching_snapshots(source_type)
    snapshots_by_source_type[source_type] ||= snapshots_scope(source_type).to_a
  end

  def snapshots_scope(source_type)
    scope = AicooDataSnapshot
      .where(source_type:)
      .where(captured_at: snapshot_time_range)

    business_id_conditions = [ "payload ->> 'business_id' = ?" ]
    business_id_values = [ business.id.to_s ]

    analytics_site_ids = AicooAnalyticsSite.where(business_id: business.id).select(:id)
    data_import_ids = DataImport.joins(:data_source)
                                .where(data_sources: { business_id: business.id })
                                .select(:id)

    if analytics_site_ids.exists?
      business_id_conditions << "payload ->> 'analytics_site_id' IN (?)"
      business_id_values << analytics_site_ids.pluck(:id).map(&:to_s)
    end

    if %w[gsc ga4].include?(source_type) && data_import_ids.exists?
      business_id_conditions << "source_id IN (?)"
      business_id_values << data_import_ids.pluck(:id)
    end

    scope.where(business_id_conditions.join(" OR "), *business_id_values)
  end

  def snapshot_time_range
    date.beginning_of_day..(date.end_of_day + SNAPSHOT_LOOKAHEAD)
  end

  def snapshots_by_source_type
    @snapshots_by_source_type ||= {}
  end

  def snapshot_metric_total(source_type, *keys)
    matching_snapshots(source_type).sum do |snapshot|
      rows = snapshot_rows(snapshot)

      if rows.any?
        rows.sum { |row| row_matches_date?(row, snapshot) ? metric_from_hash(row, *keys) : 0 }
      elsif snapshot_matches_date?(snapshot)
        metric_from_hash(snapshot_payload_hash(snapshot), *keys)
      else
        0
      end
    end
  end

  def snapshot_metric_average(source_type, *keys)
    values = matching_snapshots(source_type).flat_map do |snapshot|
      rows = snapshot_rows(snapshot)

      if rows.any?
        rows.filter_map { |row| row_matches_date?(row, snapshot) ? metric_from_hash_decimal(row, *keys) : nil }
      elsif snapshot_matches_date?(snapshot)
        [ metric_from_hash_decimal(snapshot_payload_hash(snapshot), *keys) ]
      else
        []
      end
    end.select(&:positive?)

    return 0.to_d if values.empty?

    values.sum.to_d / values.size
  end

  def snapshot_rows(snapshot)
    payload = snapshot_payload_hash(snapshot)
    rows = payload["rows"] || payload.dig("metrics", "rows")
    rows = payload["metrics"] if rows.blank? && payload["metrics"].is_a?(Array)
    Array(rows).select { |row| row.is_a?(Hash) }
  end

  def row_matches_date?(row, snapshot)
    row_date = date_from_hash(row)
    return row_date == date if row_date.present?

    snapshot_matches_date?(snapshot)
  end

  def date_from_hash(hash)
    value = DATE_KEYS.filter_map { |key| hash[key] || hash[key.to_sym] }.first
    value ||= Array(hash["keys"] || hash[:keys]).find { |item| parse_date(item).present? }

    parse_date(value)
  end

  def snapshot_matches_date?(snapshot)
    payload_date = date_from_hash(snapshot_payload_hash(snapshot))
    comparison_date = payload_date || snapshot.captured_at&.to_date

    comparison_date == date
  end

  def snapshot_business_id(snapshot)
    payload = snapshot.payload || {}
    payload["business_id"].presence&.to_i ||
      business_id_from_analytics_site(payload["analytics_site_id"]) ||
      business_id_from_data_import(snapshot)
  end

  def business_id_from_analytics_site(analytics_site_id)
    return if analytics_site_id.blank?

    AicooAnalyticsSite.find_by(id: analytics_site_id)&.business_id
  end

  def business_id_from_data_import(snapshot)
    return unless %w[gsc ga4].include?(snapshot.source_type)

    DataImport.find_by(id: snapshot.source_id)&.business&.id
  end

  def snapshot_payload_hash(snapshot)
    snapshot.payload || {}
  end

  def metric_from_hash(hash, *keys)
    metrics = hash["metrics"].is_a?(Hash) ? hash["metrics"] : {}
    keys.sum do |key|
      numeric(hash[key] || hash[key.to_sym] || metrics[key] || metrics[key.to_sym])
    end
  end

  def metric_from_hash_decimal(hash, *keys)
    metrics = hash["metrics"].is_a?(Hash) ? hash["metrics"] : {}
    keys.filter_map do |key|
      raw = hash[key] || hash[key.to_sym] || metrics[key] || metrics[key.to_sym]
      raw.to_d if raw.present?
    end.first || 0.to_d
  end

  def numeric(value)
    value.to_f.round
  end

  def parse_date(value)
    return if value.blank?

    Date.iso8601(value.to_s)
  rescue Date::Error
    parse_time_date(value)
  end

  def parse_time_date(value)
    Time.zone.parse(value.to_s)&.to_date
  rescue ArgumentError, TypeError
    nil
  end
end
