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
end

module AicooSuelogArticleExpectedValueRake
  ARTICLE_ACTION_TYPES = %w[article_create article_update new_article_candidate seo_article].freeze
  GENERATION_SOURCES = %w[suelog_db business_analyzer].freeze
  TERMINAL_STATUSES = %w[archived rejected done canceled cancelled invalid resolved superseded rejected_duplicate rejected_irrelevant].freeze
  TITLE_QUERY_PATTERN = /\A「(?<query>[^」]+)」/.freeze

  module_function

  def calculate(candidate)
    metadata = candidate.metadata.to_h.deep_stringify_keys
    Aicoo::SuelogArticleExpectedValue.call(
      business: candidate.business,
      query: source_query(candidate, metadata),
      gsc_inputs: gsc_inputs(metadata),
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
      metadata.dig("value_model", "name").to_s == "suelog_article" &&
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

  def source_query(candidate, metadata)
    [
      metadata["source_query"],
      metadata["query"],
      metadata["search_query"],
      metadata["target_query"],
      metadata.dig("article_candidate", "search_query"),
      metadata.dig("gsc_inputs", "query"),
      metadata.dig("value_model", "query"),
      candidate.title.to_s.match(TITLE_QUERY_PATTERN)&.[](:query)
    ].compact_blank.first.to_s.squish
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
      "estimated_incremental_clicks=#{result.metadata['estimated_incremental_clicks']}",
      "value_per_click_yen=#{result.metadata.dig('value_model', 'value_per_click_yen')}",
      "gsc_impressions=#{result.metadata.dig('gsc_inputs', 'impressions')}",
      "gsc_clicks=#{result.metadata.dig('gsc_inputs', 'clicks')}",
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
