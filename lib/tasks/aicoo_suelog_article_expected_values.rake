namespace :aicoo do
  desc "Recalculate Suelog article ActionCandidate expected values"
  task recalculate_suelog_article_expected_values: :environment do
    apply = ENV["APPLY"].to_s == "1"
    scope = ActionCandidate
      .includes(:business)
      .where(generation_source: AicooSuelogArticleExpectedValueRake::GENERATION_SOURCES)
      .where(action_type: AicooSuelogArticleExpectedValueRake::ARTICLE_ACTION_TYPES)

    counters = Hash.new(0)
    before_total_yen = 0
    after_total_yen = 0
    candidate_ids = []

    puts "mode=#{apply ? 'apply' : 'dry-run'}"

    scope.find_each do |candidate|
      counters[:checked] += 1

      if AicooSuelogArticleExpectedValueRake.terminal_status?(candidate)
        counters[:skipped_terminal_status] += 1
        next
      end

      unless AicooSuelogArticleExpectedValueRake.suelog_business?(candidate.business)
        counters[:skipped_non_suelog] += 1
        next
      end

      counters[:eligible] += 1
      before_value = candidate.final_expected_value_yen.to_i
      before_total_yen += before_value
      result = AicooSuelogArticleExpectedValueRake.calculate(candidate)
      after_value = result.expected_profit_yen.to_i
      after_total_yen += after_value

      if AicooSuelogArticleExpectedValueRake.insufficient_data?(result)
        counters[:insufficient_data] += 1
      elsif AicooSuelogArticleExpectedValueRake.current?(candidate, result)
        counters[:unchanged] += 1
      else
        counters[:recalculated] += 1
        candidate_ids << candidate.id
      end

      puts AicooSuelogArticleExpectedValueRake.candidate_line(candidate, result, before_value:, after_value:)

      next unless apply
      next if AicooSuelogArticleExpectedValueRake.current?(candidate, result)

      AicooSuelogArticleExpectedValueRake.apply!(candidate, result)
    rescue StandardError => e
      counters[:failed] += 1
      candidate_ids << candidate.id if defined?(candidate) && candidate&.id
      warn "candidate_id=#{candidate&.id || 'unknown'} failed=#{e.class}: #{e.message}"
    end

    puts "checked=#{counters[:checked]}"
    puts "eligible=#{counters[:eligible]}"
    puts "recalculated=#{counters[:recalculated]}"
    puts "unchanged=#{counters[:unchanged]}"
    puts "insufficient_data=#{counters[:insufficient_data]}"
    puts "skipped_terminal_status=#{counters[:skipped_terminal_status]}"
    puts "skipped_non_suelog=#{counters[:skipped_non_suelog]}"
    puts "failed=#{counters[:failed]}"
    puts "before_total_yen=#{before_total_yen}"
    puts "after_total_yen=#{after_total_yen}"
    puts "delta_yen=#{after_total_yen - before_total_yen}"
    puts "candidate_ids=#{candidate_ids.uniq.join(',')}"
  end

  desc "Diagnose Suelog GSC query rows used by SuelogArticleExpectedValue"
  task diagnose_suelog_gsc_queries: :environment do
    business = AicooSuelogArticleExpectedValueRake.suelog_business_scope.first

    if business.blank?
      puts "Business=not_found"
      next
    end

    puts "Business=#{business.name} id=#{business.id}"
    business_diagnostics = Aicoo::SuelogArticleExpectedValue.new(
      business:,
      query: "",
      gsc_inputs: {}
    ).gsc_diagnostics
    rows = Array(business_diagnostics["query_rows"])

    puts "保存先モデル=#{business_diagnostics['search_models'].join(',')}"
    puts "検索対象テーブル=#{business_diagnostics['search_tables'].join(',')}"
    puts "Query総数=#{rows.size}"
    puts "保存件数 data_imports=#{AicooSuelogArticleExpectedValueRake.suelog_gsc_data_import_count(business)} snapshots=#{AicooSuelogArticleExpectedValueRake.suelog_gsc_snapshot_count(business)}"
    puts "Query一覧"
    rows.each do |row|
      puts [
        "query=#{row['query']}",
        "clicks=#{row['clicks']}",
        "impressions=#{row['impressions']}",
        "ctr=#{row['ctr']}",
        "position=#{row['position']}",
        "landing_page=#{row['landing_page']}",
        "保存元モデル=#{row['source_model'].presence || row['source']}",
        "保存元テーブル=#{row['source_table']}"
      ].join(" ")
    end

    candidates = AicooSuelogArticleExpectedValueRake.suelog_article_candidate_scope(business)
    candidates = candidates.where(id: ENV["CANDIDATE_IDS"].to_s.split(",").map(&:presence).compact) if ENV["CANDIDATE_IDS"].present?
    candidates = candidates.where(id: [ 330, 331, 332, 333, 334, 335 ]) if ENV["CANDIDATE_IDS"].blank?

    puts "候補一致状況"
    candidates.find_each do |candidate|
      metadata = candidate.metadata.to_h.deep_stringify_keys
      source_query, query_source = AicooSuelogArticleExpectedValueRake.source_query_with_source(candidate, metadata)
      diagnostics = Aicoo::SuelogArticleExpectedValue.new(
        business:,
        query: source_query,
        gsc_inputs: AicooSuelogArticleExpectedValueRake.gsc_inputs(metadata).merge("query_source" => query_source)
      ).gsc_diagnostics

      puts [
        "candidate_id=#{candidate.id}",
        "source_query=#{source_query}",
        "query_source=#{query_source}",
        "一致候補数=#{diagnostics['query_rows_count']}",
        "exact一致数=#{diagnostics['exact_count']}",
        "normalized一致数=#{diagnostics['normalized_count']}",
        "partial一致数=#{diagnostics['partial_count']}",
        "一致したQuery=#{diagnostics['matched_query']}",
        "保存モデル=#{Array(diagnostics['query_rows']).find { |row| row['query'] == diagnostics['matched_query'] }&.dig('source_model')}",
        "match_type=#{diagnostics['match_type']}",
        "fallback理由=#{diagnostics['fallback_reason']}"
      ].join(" ")
    end
  end

  desc "Diagnose article opportunities by integrated GSC, GA4, ShopClick and Learning analysis"
  task diagnose_article_opportunity: :environment do
    business = AicooSuelogArticleExpectedValueRake.suelog_business_scope.first

    if business.blank?
      puts "Business=not_found"
      next
    end

    puts "Business=#{business.name} id=#{business.id}"
    candidates = AicooSuelogArticleExpectedValueRake.suelog_article_candidate_scope(business)
    candidates = candidates.where(id: ENV["CANDIDATE_IDS"].to_s.split(",").map(&:presence).compact) if ENV["CANDIDATE_IDS"].present?
    candidates = candidates.limit(20) if ENV["CANDIDATE_IDS"].blank?

    candidates.find_each do |candidate|
      metadata = candidate.metadata.to_h.deep_stringify_keys
      result = AicooSuelogArticleExpectedValueRake.calculate(candidate)
      value_model = result.metadata["value_model"].to_h

      puts [
        "candidate_id=#{candidate.id}",
        "title=#{candidate.title.to_s.squish}",
        "theme=#{result.metadata['source_query']}",
        "analysis=#{result.metadata['analysis'].to_json}",
        "signals=#{result.metadata['signals'].to_json}",
        "opportunity_type=#{result.metadata['opportunity_type']}",
        "expected_effect=#{result.metadata['expected_effect'].to_json}",
        "theme_cluster=#{result.metadata['theme_cluster'].to_json}",
        "利用Query=#{Array(result.metadata['matched_queries']).join('|')}",
        "関連記事GA4=#{result.metadata['ga4_inputs'].to_json}",
        "ShopClick=#{result.metadata['shopclick_inputs'].to_json}",
        "Learning=#{result.metadata['learning_inputs'].to_json}",
        "learning_adjustment=#{result.metadata['learning_adjustment']}",
        "expected_profit=#{result.expected_profit_yen}",
        "reason=#{result.metadata['calculation_reason']}",
        "value_model=#{value_model['name']}"
      ].join(" ")
    end
  end
end

module AicooSuelogArticleExpectedValueRake
  ARTICLE_ACTION_TYPES = %w[article_create article_update new_article_candidate seo_article].freeze
  GENERATION_SOURCES = %w[suelog_db business_analyzer].freeze
  TERMINAL_STATUSES = %w[archived rejected done canceled cancelled invalid resolved superseded rejected_duplicate rejected_irrelevant].freeze
  TITLE_QUERY_PATTERN = /\A「(?<query>[^」]+)」/.freeze

  module_function

  def calculate(candidate)
    metadata = candidate.metadata.to_h.deep_stringify_keys
    query, query_source = source_query_with_source(candidate, metadata)
    Aicoo::ArticleOpportunityAnalyzer.call(
      business: candidate.business,
      query:,
      gsc_inputs: gsc_inputs(metadata).merge("query_source" => query_source),
      ga4_inputs: ga4_inputs(metadata),
      shopclick_inputs: shopclick_inputs(metadata),
      article_inputs: article_inputs(metadata),
      success_probability: candidate.success_probability
    )
  end

  def apply!(candidate, result)
    value = result.expected_profit_yen.to_i
    before = {
      "immediate_value_yen" => candidate.immediate_value_yen.to_i,
      "expected_profit_yen" => candidate.expected_profit_yen.to_i,
      "expected_revenue_value_yen" => candidate.expected_revenue_value_yen.to_i,
      "expected_total_value_yen" => candidate.expected_total_value_yen.to_i,
      "final_expected_value_yen" => candidate.final_expected_value_yen.to_i
    }
    candidate.assign_attributes(
      immediate_value_yen: value,
      expected_profit_yen: value,
      expected_revenue_value_yen: value,
      expected_total_value_yen: value,
      final_expected_value_yen: value,
      metadata: candidate.metadata.to_h.deep_stringify_keys.merge(result.metadata).merge(
        "seo_expected_value_skipped" => true,
        "skip_reason" => "suelog_generated",
        "generator_name" => candidate.metadata.to_h["created_by"].presence || candidate.metadata.to_h["generator"].presence || candidate.generation_source,
        "generation_source" => candidate.generation_source,
        "suelog_article_value_recalculated_at" => Time.current.iso8601,
        "suelog_article_value_recalculation_before" => before
      )
    )
    candidate.save!
  end

  def current?(candidate, result)
    metadata = candidate.metadata.to_h
    value = result.expected_profit_yen.to_i
    candidate.expected_profit_yen.to_i == value &&
      candidate.expected_revenue_value_yen.to_i == value &&
      candidate.expected_total_value_yen.to_i == value &&
      candidate.final_expected_value_yen.to_i == value &&
      metadata["seo_expected_value_skipped"] == true &&
      metadata["skip_reason"].to_s == "suelog_generated" &&
      metadata.dig("value_model", "name").to_s == "article_opportunity_analyzer" &&
      metadata["calculation_reason"].to_s == result.metadata["calculation_reason"].to_s
  end

  def insufficient_data?(result)
    result.expected_profit_yen.to_i.zero? &&
      result.metadata.dig("gsc_inputs", "impressions").to_i.zero? &&
      result.metadata["estimated_incremental_clicks"].to_d.zero?
  end

  def terminal_status?(candidate)
    candidate.status.to_s.in?(TERMINAL_STATUSES)
  end

  def suelog_business?(business)
    return false unless business

    metadata = business.metadata.to_h
    values = [
      business.name,
      business.project_key,
      business.repository_name,
      business.local_project_path,
      business.source,
      business.gsc_site_url,
      metadata["source_app"],
      metadata["source_system"],
      metadata["business_key"],
      metadata["slug"],
      metadata["project_key"]
    ].compact.map(&:to_s)
    return true if values.any? { |value| value.match?(/吸えログ|suelog|sue-log/i) }

    business.respond_to?(:source_app_connections) &&
      business.source_app_connections.where(source_app: %w[suelog sue-log 吸えログ]).exists?
  end

  def suelog_business_scope
    Business.kept.order(:id).select { |business| suelog_business?(business) }
  end

  def suelog_article_candidate_scope(business)
    business.action_candidates
      .where(generation_source: GENERATION_SOURCES)
      .where(action_type: ARTICLE_ACTION_TYPES)
      .where.not(status: TERMINAL_STATUSES)
  end

  def suelog_gsc_data_import_count(business)
    data_import_ids = business.data_sources.where(source_type: "gsc").joins(:data_imports).pluck("data_imports.id")
    analytics_site_ids = AicooAnalyticsSite.where(business_id: business.id).pluck(:id)
    analytics_site_ids += AicooAnalyticsSite.where(gsc_site_url: business.gsc_site_url).pluck(:id) if business.gsc_site_url.present?
    data_import_ids += DataImport.joins(:data_source).where(data_sources: { source_type: "gsc" }, aicoo_analytics_site_id: analytics_site_ids.uniq).pluck(:id) if analytics_site_ids.any?
    data_import_ids.uniq.size
  end

  def suelog_gsc_snapshot_count(business)
    analytics_site_ids = AicooAnalyticsSite.where(business_id: business.id).pluck(:id)
    analytics_site_ids += AicooAnalyticsSite.where(gsc_site_url: business.gsc_site_url).pluck(:id) if business.gsc_site_url.present?
    AicooDataSnapshot.where(source_type: "gsc").select do |snapshot|
      payload = snapshot.payload.to_h
      source_record = snapshot.source_record
      payload["business_id"].to_i == business.id ||
        analytics_site_ids.map(&:to_s).include?(payload["analytics_site_id"].to_s) ||
        snapshot.source_id.to_i == business.id ||
        (source_record.respond_to?(:aicoo_analytics_site_id) && analytics_site_ids.include?(source_record.aicoo_analytics_site_id))
    end.size
  end

  def source_query(candidate, metadata)
    source_query_with_source(candidate, metadata).first
  end

  def source_query_with_source(candidate, metadata)
    [
      [ metadata["source_query"], "metadata.source_query" ],
      [ metadata["query"], "metadata.query" ],
      [ metadata["keyword"], "metadata.keyword" ],
      [ metadata["article_query"], "metadata.article_query" ],
      [ candidate.title.to_s.match(TITLE_QUERY_PATTERN)&.[](:query), "title" ],
      [ metadata["search_query"], "metadata.search_query" ],
      [ metadata["target_query"], "metadata.target_query" ],
      [ metadata.dig("article_candidate", "search_query"), "metadata.article_candidate.search_query" ],
      [ metadata.dig("gsc_inputs", "query"), "metadata.gsc_inputs.query" ],
      [ metadata.dig("value_model", "query"), "metadata.value_model.query" ]
    ].each do |value, source|
      normalized = value.to_s.squish
      return [ normalized, source ] if normalized.present?
    end

    [ "", "blank" ]
  end

  def gsc_inputs(metadata)
    existing = metadata["gsc_inputs"].to_h
    {
      "impressions" => first_numeric(existing["impressions"], metadata["impressions"], metadata["gsc_impressions"]),
      "clicks" => first_numeric(existing["clicks"], metadata["clicks"], metadata["gsc_clicks"]),
      "ctr" => first_numeric(existing["current_ctr"], existing["ctr"], metadata["current_ctr"], metadata["ctr"], metadata["ctr_percent"]),
      "position" => first_numeric(existing["position"], metadata["position"], metadata["average_position"]),
      "target_ctr" => first_numeric(existing["target_ctr"], metadata["target_ctr"]),
      "landing_page" => first_present(existing["landing_page"], metadata["landing_page"], metadata["target_url"])
    }.compact
  end

  def ga4_inputs(metadata)
    existing = metadata["ga4_inputs"].to_h
    {
      "pageviews" => first_numeric(existing["pageviews"], existing["views"], metadata["ga4_pageviews"], metadata["pageviews"]),
      "active_users" => first_numeric(existing["active_users"], existing["users"], metadata["ga4_active_users"], metadata["active_users"], metadata["users"]),
      "engagement_seconds" => first_numeric(existing["engagement_seconds"], metadata["ga4_engagement_seconds"], metadata["average_engagement_time_seconds"])
    }.compact
  end

  def shopclick_inputs(metadata)
    existing = metadata["shopclick_inputs"].to_h
    {
      "recent_shop_clicks" => first_numeric(existing["recent_shop_clicks"], existing["clicks"], metadata["recent_clicks"], metadata["shop_clicks"]),
      "matched_shop_count" => first_numeric(existing["matched_shop_count"], existing["shop_count"], metadata["shops_count"], Array(metadata["candidate_shops"]).size),
      "lookback_days" => first_numeric(existing["lookback_days"], 90)
    }.compact
  end

  def article_inputs(metadata)
    {
      "article_id" => metadata["article_id"],
      "article_title" => metadata["article_title"],
      "article_path" => metadata["target_url"],
      "impressions" => metadata.dig("article_candidate", "expected_pv")
    }.compact
  end

  def candidate_line(candidate, result, before_value:, after_value:)
    [
      "candidate_id=#{candidate.id}",
      "title=#{candidate.title.to_s.squish}",
      "generation_source=#{candidate.generation_source}",
      "before_expected_profit_yen=#{candidate.expected_profit_yen.to_i}",
      "after_expected_profit_yen=#{after_value}",
      "before_final_expected_value_yen=#{before_value}",
      "after_final_expected_value_yen=#{after_value}",
      "value_model_name=#{result.metadata.dig('value_model', 'name')}",
      "source_query=#{result.metadata['source_query']}",
      "matched_query=#{result.metadata['matched_query']}",
      "match_type=#{result.metadata['query_match_type']}",
      "query_rows_count=#{result.metadata['gsc_query_rows_count']}",
      "exact_count=#{result.metadata['gsc_query_exact_count']}",
      "normalized_count=#{result.metadata['gsc_query_normalized_count']}",
      "partial_count=#{result.metadata['gsc_query_partial_count']}",
      "fallback_reason=#{result.metadata.dig('gsc_inputs', 'fallback_reason')}",
      "estimated_incremental_clicks=#{result.metadata['estimated_incremental_clicks']}",
      "value_per_click_yen=#{result.metadata.dig('value_model', 'value_per_click_yen')}",
      "gsc_impressions=#{result.metadata.dig('gsc_inputs', 'impressions')}",
      "gsc_clicks=#{result.metadata.dig('gsc_inputs', 'clicks')}",
      "gsc_ctr=#{result.metadata.dig('gsc_inputs', 'current_ctr')}",
      "gsc_position=#{result.metadata.dig('gsc_inputs', 'position')}",
      "ga4_pageviews=#{result.metadata.dig('ga4_inputs', 'pageviews')}",
      "shop_clicks=#{result.metadata.dig('shopclick_inputs', 'recent_shop_clicks')}",
      "calculation_reason=#{result.metadata['calculation_reason']}",
      "status=#{candidate.status}"
    ].join(" ")
  end

  def first_present(*values)
    values.find { |value| value.present? }
  end

  def first_numeric(*values)
    values.find { |value| value.present? && value.respond_to?(:to_d) }
  end
end
