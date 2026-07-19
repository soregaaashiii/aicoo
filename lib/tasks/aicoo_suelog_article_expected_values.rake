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

  desc "Diagnose whether Suelog GSC, GA4, ShopClick and Article data are saved and joinable by article URL"
  task diagnose_suelog_article_data_sources: :environment do
    business = AicooSuelogArticleExpectedValueRake.suelog_business_scope.first

    if business.blank?
      puts "Business=not_found"
      next
    end

    puts Aicoo::SuelogArticleDataSourcesDiagnostic.call(business:)
  end

  desc "Diagnose Suelog GA4 fetch request, response and saved page data end-to-end without modifying data"
  task diagnose_suelog_ga4_fetch_e2e: :environment do
    business = AicooSuelogArticleExpectedValueRake.suelog_business_scope.first

    if business.blank?
      puts "Business=not_found"
      next
    end

    puts Aicoo::SuelogGa4FetchE2eDiagnostic.call(business:)
  end

  desc "Resync Suelog GA4 page data after Google OAuth reconnect. Dry-run by default; use APPLY=1 to save."
  task resync_suelog_ga4: :environment do
    business = AicooSuelogArticleExpectedValueRake.suelog_business_scope.first

    if business.blank?
      puts "Business=not_found"
      next
    end

    result = Aicoo::SuelogGa4Resync.call(business:, apply: ENV["APPLY"] == "1")
    puts "mode=#{result.mode}"
    puts "business_id=#{result.business&.id || '-'}"
    puts "business_name=#{result.business&.name || '-'}"
    puts "ga4_property_id=#{result.setting&.property_id || '-'}"
    puts "date_range=#{result.start_date}..#{result.end_date}"
    puts "oauth_usable=#{result.oauth_usable}"
    puts "property_matches_suelog=#{result.property_matches_suelog}"
    puts "business_matches_suelog=#{result.business_matches_suelog}"
    puts "resync_allowed=#{result.resync_allowed}"
    puts "blocking_reasons=#{result.blocking_reasons.join(' / ').presence || '-'}"
    puts "api_row_count=#{result.api_row_count}"
    puts "saved_row_count=#{result.saved_row_count}"
    puts "article_row_count=#{result.article_row_count}"
    puts "shop_row_count=#{result.shop_row_count}"
    puts "lp_row_count=#{result.lp_row_count}"
    puts "host_counts=#{result.host_counts.map { |host, count| "#{host}:#{count}" }.join(',').presence || '-'}"
    puts "excluded_counts=#{result.excluded_counts.map { |reason, count| "#{reason}:#{count}" }.join(',').presence || '-'}"
    puts "accepted_rows=#{result.saved_row_count}"
    puts "rejected_rows=#{result.excluded_counts.values.sum}"
    puts "accepted_reason_counts=#{result.accepted_reason_counts.map { |reason, count| "#{reason}:#{count}" }.join(',').presence || '-'}"
    puts "rejected_reason_counts=#{result.rejected_reason_counts.map { |reason, count| "#{reason}:#{count}" }.join(',').presence || '-'}"
    puts "host_judgement_expected_hosts=#{Aicoo::SuelogGa4Resync::ALLOWED_HOSTS.join(',')}"
    puts "host_judgement_method=hostName -> pageLocation host -> property/business/source-setting"
    puts "row_diagnostics:"
    result.row_diagnostics.each do |row|
      puts [
        "row_index=#{row.fetch(:row_index)}",
        "hostName=#{row.fetch(:hostName).presence || '-'}",
        "pagePath=#{row.fetch(:pagePath).presence || '-'}",
        "pageLocation=#{row.fetch(:pageLocation).presence || '-'}",
        "dimensionValues=#{row.fetch(:dimensionValues).inspect}",
        "normalized_host=#{row.fetch(:normalized_host).presence || '-'}",
        "normalized_path=#{row.fetch(:normalized_path).presence || '-'}",
        "host_match_source=#{row.fetch(:host_match_source)}",
        "accepted=#{row.fetch(:accepted)}",
        "accepted_reason=#{row.fetch(:accepted_reason).presence || '-'}",
        "exclude_reason=#{row.fetch(:exclude_reason).presence || '-'}"
      ].join(" ")
    end
    puts "data_import_id=#{result.data_import_id || '-'}"
    puts "snapshot_id=#{result.snapshot_id || '-'}"
    puts "analytics_fetch_run_id=#{result.analytics_fetch_run_id || '-'}"
    puts "google_api_import_run_id=#{result.google_api_import_run_id || '-'}"
  end

  desc "Check Suelog GA4 data integrity after resync"
  task check_suelog_ga4_integrity: :environment do
    business = AicooSuelogArticleExpectedValueRake.suelog_business_scope.first

    if business.blank?
      puts "Business=not_found"
      next
    end

    result = Aicoo::SuelogGa4DataIntegrityCheck.call(business:)
    puts "business_id=#{result.business_id || '-'}"
    puts "property_id=#{result.property_id || '-'}"
    puts "host=#{result.host || '-'}"
    puts "latest_fetch_status=#{result.latest_fetch_status}"
    puts "latest_success_at=#{result.latest_success_at || '-'}"
    puts "latest_failure_at=#{result.latest_failure_at || '-'}"
    puts "oauth_usable=#{result.oauth_usable}"
    puts "stored_row_count=#{result.stored_row_count}"
    puts "article_row_count=#{result.article_row_count}"
    puts "shop_row_count=#{result.shop_row_count}"
    puts "lp_row_count=#{result.lp_row_count}"
    puts "mixed_business_row_count=#{result.mixed_business_row_count}"
    puts "stale_row_count=#{result.stale_row_count}"
    puts "ga4_matched_articles=#{result.ga4_matched_articles}"
    puts "ga4_unmatched_articles=#{result.ga4_unmatched_articles}"
    puts "ga4_article_match_rate=#{result.ga4_article_match_rate}%"
    puts "fully_joinable_article_count=#{result.fully_joinable_article_count}"
    puts "integrity_status=#{result.integrity_status}"
    puts "blocking_reasons=#{result.blocking_reasons.join(' / ').presence || '-'}"
  end

  desc "Build per-article analytics snapshots for Suelog. Dry-run by default; use APPLY=1 to save."
  task build_article_analytics_snapshot: :environment do
    business = AicooSuelogArticleExpectedValueRake.suelog_business_scope.first

    if business.blank?
      puts "Business=not_found"
      next
    end

    result = Aicoo::ArticleAnalyticsSnapshotBuilder.call(business:, apply: ENV["APPLY"] == "1")
    AicooArticleAnalyticsSnapshotRake.print_result(result)
  end

  desc "Archive duplicate GSC/GA4 metric snapshots. Dry-run by default; use APPLY=1 to archive duplicates."
  task cleanup_metric_snapshots: :environment do
    result = Aicoo::SnapshotCleanup.call(apply: ENV["APPLY"] == "1")
    AicooArticleAnalyticsSnapshotRake.print_cleanup_result(result)
  end

  desc "Diagnose saved per-article analytics snapshots for Suelog"
  task diagnose_article_analytics_snapshot: :environment do
    business = AicooSuelogArticleExpectedValueRake.suelog_business_scope.first

    if business.blank?
      puts "Business=not_found"
      next
    end

    result = Aicoo::ArticleAnalyticsSnapshotBuilder.new(business:).diagnostic_result
    AicooArticleAnalyticsSnapshotRake.print_result(result)
  end

  desc "Compare legacy article analyzer with the new ArticleAnalyticsSnapshot-based analyzer. Dry-run by default; use APPLY=1 to save comparison-only candidates."
  task compare_article_analyzers: :environment do
    business = AicooSuelogArticleExpectedValueRake.suelog_business_scope.first

    if business.blank?
      puts "Business=not_found"
      next
    end

    result = Aicoo::ArticleOpportunityAnalyzer.compare_with_legacy(
      business:,
      apply: ENV["APPLY"] == "1",
      limit: ENV["LIMIT"]
    )
    AicooArticleAnalyticsSnapshotRake.print_analyzer_comparison(result)
  end

  desc "Diagnose ArticleOpportunityAnalyzer SEO/CTR/SearchDemand score inputs from ArticleAnalyticsSnapshot"
  task diagnose_article_opportunity_scores: :environment do
    business = AicooSuelogArticleExpectedValueRake.suelog_business_scope.first

    if business.blank?
      puts "Business=not_found"
      next
    end

    runner = Aicoo::ArticleOpportunityAnalyzer::SnapshotRunner.new(
      business:,
      limit: ENV["LIMIT"]
    )
    rows = runner.score_diagnostics
    AicooArticleAnalyticsSnapshotRake.print_article_opportunity_score_diagnostics(business, rows, runner.business_score_statistics)
  end

  desc "Diagnose ArticleOpportunityAnalyzer candidates connected to Today"
  task diagnose_article_opportunity_today: :environment do
    business = AicooSuelogArticleExpectedValueRake.suelog_business_scope.first

    if business.blank?
      puts "Business=not_found"
      next
    end

    result = Aicoo::ArticleOpportunityTodayConnector.new(
      business:,
      apply: ENV["APPLY"] == "1",
      limit: ENV["LIMIT"]
    ).call
    AicooArticleAnalyticsSnapshotRake.print_article_opportunity_today_result(result)
  end
end

module AicooArticleAnalyticsSnapshotRake
  module_function

  def print_result(result)
    puts "mode=#{result.mode}"
    puts "business_id=#{result.business&.id || '-'}"
    puts "business_name=#{result.business&.name || '-'}"
    puts "snapshot_storage=AicooDataSnapshot source_type=article_analytics source_id=suelog_article_id"
    puts "published_article_count=#{result.published_article_count}"
    puts "snapshot_count=#{result.snapshot_count}"
    puts "created_count=#{result.created_count}"
    puts "updated_count=#{result.updated_count}"
    puts "gsc_joined_count=#{result.gsc_joined_count}"
    puts "ga4_joined_count=#{result.ga4_joined_count}"
    puts "shop_click_joined_count=#{result.shop_click_joined_count}"
    puts "three_source_joined_count=#{result.three_source_joined_count}"
    puts "failed_count=#{result.failed_count}"
    puts "snapshot_ids=#{result.snapshot_ids.join(',').presence || '-'}"
    puts "available_false_counts=#{result.unavailable_counts.map { |source, count| "#{source}:#{count}" }.join(',').presence || '-'}"
    puts "gsc_snapshot_quality=#{AicooArticleAnalyticsSnapshotRake.snapshot_quality_line(result.gsc_snapshot_quality)}"
    puts "ga4_snapshot_quality=#{AicooArticleAnalyticsSnapshotRake.snapshot_quality_line(result.ga4_snapshot_quality)}"
    puts "gsc_duplicate_sources:"
    print_duplicate_sources(result.gsc_snapshot_quality)
    puts "ga4_duplicate_sources:"
    print_duplicate_sources(result.ga4_snapshot_quality)
    puts "article_info_rates:"
    result.article_info_rates.each do |field, stats|
      puts "#{field}=#{stats['present']}/#{stats['total']} #{stats['rate']}%"
    end
    print_article_content_diagnostics(result.article_content_diagnostics)
    puts "gsc_duplicate_candidates:"
    print_duplicate_candidates(result.gsc_duplicate_candidates)
    puts "ga4_duplicate_candidates:"
    print_duplicate_candidates(result.ga4_duplicate_candidates)
    puts "snapshot_samples:"
    result.sample_payloads.first(5).each do |payload|
      puts JSON.pretty_generate(
        payload.slice("article_id", "normalized_path", "gsc", "ga4", "shop_click", "article", "learning")
      )
    end
    puts "missing_articles:"
    if result.missing_articles.empty?
      puts "-"
    else
      result.missing_articles.each do |row|
        puts [
          "article_id=#{row['article_id']}",
          "path=#{row['path'] || '-'}",
          "title=#{row['title'].to_s.squish.presence || '-'}",
          "missing=#{Array(row['missing']).join(',')}"
        ].join(" ")
      end
    end
  end

  def print_duplicate_candidates(rows)
    if rows.empty?
      puts "-"
      return
    end

    rows.each do |row|
      puts [
        "page=#{row['page'] || '-'}",
        "normalized_path=#{row['normalized_path'] || '-'}",
        "query=#{row['query'] || '-'}",
        "date=#{row['date'] || '-'}",
        "duplicate_count=#{row['duplicate_count']}",
        "source_models=#{Array(row['source_models']).join('|')}",
        "source_ids=#{Array(row['source_ids']).join('|')}"
      ].join(" ")
    end
  end

  def snapshot_quality_line(quality)
    return "-" if quality.blank?

    [
      "total_snapshot_count=#{quality['total_snapshot_count'] || quality['snapshot_count']}",
      "active_snapshot_count=#{quality['active_snapshot_count'] || quality['snapshot_count']}",
      "archived_snapshot_count=#{quality['archived_snapshot_count'].to_i}",
      "ignored_snapshot_count=#{quality['ignored_snapshot_count'].to_i}",
      "duplicate_snapshot_count=#{quality['duplicate_snapshot_count']}",
      "duplicate_group_count=#{quality['duplicate_group_count']}",
      "duplicate_rate=#{quality['duplicate_rate']}%"
    ].join(" ")
  end

  def print_duplicate_sources(quality)
    rows = Array(quality && quality["duplicate_sources"])
    if rows.empty?
      puts "-"
      return
    end

    rows.each do |row|
      puts [
        "snapshot_ids=#{Array(row['snapshot_ids']).join('|')}",
        "source_ids=#{Array(row['source_ids']).join('|')}",
        "data_import_ids=#{Array(row['data_import_ids']).join('|')}",
        "source_models=#{Array(row['source_models']).join('|')}",
        "imported_at=#{Array(row['imported_at']).join('|')}"
      ].join(" ")
    end
  end

  def print_article_content_diagnostics(diagnostics)
    diagnostics ||= {}
    puts "article_content_diagnostics:"
    puts "article_columns=#{Array(diagnostics['article_columns']).join(',').presence || '-'}"
    puts "article_associations=#{Array(diagnostics['article_associations']).join(',').presence || '-'}"
    puts "content_tables=#{Array(diagnostics['content_tables']).join(',').presence || '-'}"
    puts "content_source_counts=#{diagnostics.fetch('content_source_counts', {}).map { |source, count| "#{source}:#{count}" }.join(',').presence || '-'}"
    puts "content_present_count=#{diagnostics['content_present_count'].to_i}"
    puts "content_present_rate=#{diagnostics['content_present_rate'].to_f}%"
    puts "internal_link_present_count=#{diagnostics['internal_link_present_count'].to_i}"
    puts "internal_link_present_rate=#{diagnostics['internal_link_present_rate'].to_f}%"
    puts "missing_content_articles:"
    rows = Array(diagnostics["missing_content_articles"])
    if rows.empty?
      puts "-"
    else
      rows.each do |row|
        puts [
          "article_id=#{row['article_id']}",
          "path=#{row['path'] || '-'}",
          "title=#{row['title'].to_s.squish.presence || '-'}"
        ].join(" ")
      end
    end
  end

  def print_cleanup_result(result)
    puts "mode=#{result.mode}"
    puts "checked=#{result.checked_count}"
    puts "active=#{result.active_count}"
    puts "already_archived=#{result.already_archived_count}"
    puts "archived=#{result.archived_count}"
    puts "duplicate_groups=#{result.duplicate_group_count}"
    puts "duplicate_snapshots=#{result.duplicate_snapshot_count}"
    puts "before_duplicate_rate=#{result.before_duplicate_rate}%"
    puts "after_duplicate_rate=#{result.after_duplicate_rate}%"
    puts "failed=#{result.failed_count}"
    puts "archived_snapshot_ids=#{result.archived_snapshot_ids.join(',').presence || '-'}"
    puts "source_type_summaries:"
    result.source_type_summaries.each do |source_type, summary|
      puts [
        "source_type=#{source_type}",
        "total=#{summary[:total_count] || summary['total_count']}",
        "active=#{summary[:active_count] || summary['active_count']}",
        "archived=#{summary[:archived_count] || summary['archived_count']}",
        "ignored=#{summary[:ignored_count] || summary['ignored_count']}",
        "duplicate_groups=#{summary[:duplicate_group_count] || summary['duplicate_group_count']}",
        "duplicate_snapshots=#{summary[:duplicate_snapshot_count] || summary['duplicate_snapshot_count']}",
        "duplicate_rate=#{summary[:duplicate_rate] || summary['duplicate_rate']}%"
      ].join(" ")
    end
  end

  def print_analyzer_comparison(result)
    puts "mode=#{result.mode}"
    puts "business_id=#{result.business&.id || '-'}"
    puts "business_name=#{result.business&.name || '-'}"
    puts "legacy_analyzer=existing_expected_value_article_candidates"
    puts "new_analyzer=Aicoo::ArticleOpportunityAnalyzer.from_snapshots"
    puts "legacy_article_count=#{result.legacy_article_count}"
    puts "new_article_count=#{result.new_article_count}"
    puts "legacy_action_candidate_count=#{result.legacy_action_candidate_count}"
    puts "new_action_candidate_count=#{result.new_action_candidate_count}"
    puts "created_count=#{result.created_count}"
    puts "failed_count=#{result.failed_count}"
    puts "match_count=#{result.match_count}"
    puts "match_rate=#{result.match_rate}%"
    puts "candidate_ids=#{result.candidate_ids.join(',').presence || '-'}"
    puts "new_article_results_top10:"
    result.article_results.sort_by { |row| [ -row.expected_improvement_score.to_d, -row.opportunity_score.to_d ] }.first(10).each do |row|
      puts [
        "snapshot_id=#{row.snapshot_id}",
        "article_id=#{row.article_id}",
        "path=#{row.normalized_path || '-'}",
        "opportunity_score=#{row.opportunity_score}",
        "search_demand_score=#{row.search_demand_score}",
        "improvement_potential_score=#{row.improvement_potential_score}",
        "expected_improvement_score=#{row.expected_improvement_score}",
        "success_probability=#{row.metadata['success_probability'] || '-'}",
        "estimated_work_hours=#{row.metadata['estimated_work_hours'] || '-'}",
        "business_value=#{row.metadata['business_value'] || '-'}",
        "seo=#{row.score_breakdown['seo_opportunity']}",
        "ctr=#{row.score_breakdown['ctr_opportunity']}",
        "pv=#{row.score_breakdown['pv_opportunity']}",
        "click=#{row.score_breakdown['click_opportunity']}",
        "content=#{row.score_breakdown['content_opportunity']}",
        "learning=#{row.score_breakdown['learning_confidence']}",
        "business_impression_rank=#{row.metadata.dig('score_diagnostics', 'business_relative', 'impression_rank') || '-'}",
        "business_ctr_rank=#{row.metadata.dig('score_diagnostics', 'business_relative', 'ctr_rank') || '-'}",
        "business_search_demand_rank=#{row.metadata.dig('score_diagnostics', 'business_relative', 'search_demand_rank') || '-'}",
        "seo_reason=#{row.metadata.dig('score_diagnostics', 'seo_reason') || '-'}",
        "ctr_reason=#{row.metadata.dig('score_diagnostics', 'ctr_reason') || '-'}",
        "opportunities=#{row.opportunities.map { |opportunity| opportunity['opportunity_type'] }.join('|').presence || '-'}",
        "ranking_reason=#{row.metadata['ranking_reason'].to_s.squish.presence || '-'}",
        "title=#{row.title.to_s.squish.presence || '-'}"
      ].join(" ")
      Array(row.opportunities).each do |opportunity|
        puts [
          "  improvement=#{opportunity['label'] || '-'}",
          "type=#{opportunity['opportunity_type'] || '-'}",
          "score=#{opportunity['score'] || 0}",
          "search_demand_score=#{opportunity['search_demand_score'] || '-'}",
          "improvement_potential_score=#{opportunity['improvement_potential_score'] || '-'}",
          "expected_improvement_score=#{opportunity['expected_improvement_score'] || 0}",
          "success_probability=#{opportunity['success_probability'] || '-'}",
          "estimated_work_hours=#{opportunity['estimated_work_hours'] || '-'}",
          "business_value=#{opportunity['business_value'] || '-'}",
          "reason=#{opportunity['reason'].to_s.squish.presence || '-'}",
          "ranking_reason=#{opportunity['ranking_reason'].to_s.squish.presence || '-'}",
          "next=#{opportunity['next_action'].to_s.squish.presence || '-'}"
        ].join(" ")
      end
    end
    puts "rank_differences:"
    if result.rank_differences.empty?
      puts "-"
    else
      result.rank_differences.first(50).each do |row|
        puts [
          "article=#{row['article_key'] || '-'}",
          "legacy_candidate_id=#{row['legacy_candidate_id'] || '-'}",
          "legacy_rank=#{row['legacy_rank'] || '-'}",
          "legacy_expected_value_yen=#{row['legacy_expected_value_yen'] || 0}",
          "new_snapshot_id=#{row['new_snapshot_id'] || '-'}",
          "new_rank=#{row['new_rank'] || '-'}",
          "new_opportunity_score=#{row['new_opportunity_score'] || '-'}",
          "new_search_demand_score=#{row['new_search_demand_score'] || '-'}",
          "new_improvement_potential_score=#{row['new_improvement_potential_score'] || '-'}",
          "new_expected_improvement_score=#{row['new_expected_improvement_score'] || '-'}",
          "rank_delta=#{row['rank_delta'] || '-'}",
          "new_opportunities=#{Array(row['new_opportunities']).join('|').presence || '-'}"
        ].join(" ")
      end
    end
  end

  def print_article_opportunity_score_diagnostics(business, rows, business_statistics = {})
    puts "business_id=#{business.id}"
    puts "business_name=#{business.name}"
    puts "checked=#{rows.size}"
    puts [
      "business_statistics",
      "article_count=#{business_statistics['article_count'] || 0}",
      "impressions_median=#{business_statistics['impressions_median'] || 0}",
      "impressions_average=#{business_statistics['impressions_average'] || 0}",
      "impressions_top_20_percent_threshold=#{business_statistics['impressions_top_20_percent_threshold'] || 0}",
      "impressions_top_30_percent_threshold=#{business_statistics['impressions_top_30_percent_threshold'] || 0}",
      "ctr_median=#{business_statistics['ctr_median'] || 0}",
      "ctr_average=#{business_statistics['ctr_average'] || 0}",
      "position_median=#{business_statistics['position_median'] || 0}",
      "position_average=#{business_statistics['position_average'] || 0}"
    ].join(" ")
    rows.each do |row|
      gsc = row["gsc"].to_h
      ga4 = row["ga4"].to_h
      shop_click = row["shop_click"].to_h
      relative = row["business_relative"].to_h
      formula = row["expected_improvement_formula"].to_h
      puts [
        "article_id=#{row['article_id']}",
        "title=#{row['title'].to_s.squish.presence || '-'}",
        "snapshot_id=#{row['snapshot_id']}",
        "gsc.available=#{gsc['available']}",
        "impressions=#{gsc['impressions'] || '-'}",
        "clicks=#{gsc['clicks'] || '-'}",
        "ctr=#{gsc['ctr'] || '-'}",
        "average_position=#{gsc['average_position'] || '-'}",
        "query_count=#{gsc['query_count'] || '-'}",
        "ga4.pageviews=#{ga4['pageviews'] || '-'}",
        "shop_click.total_clicks=#{shop_click['total_clicks'] || '-'}",
        "business_impression_rank=#{relative['impression_rank'] || '-'}",
        "business_ctr_rank=#{relative['ctr_rank'] || '-'}",
        "business_search_demand_rank=#{relative['search_demand_rank'] || '-'}"
      ].join(" ")
      puts [
        "  seo_opportunity=#{row['seo_opportunity']}",
        "seo_condition_result=#{row['seo_condition_result']}",
        "seo_reason=#{row['seo_reason']}"
      ].join(" ")
      puts [
        "  ctr_opportunity=#{row['ctr_opportunity']}",
        "ctr_condition_result=#{row['ctr_condition_result']}",
        "ctr_reason=#{row['ctr_reason']}"
      ].join(" ")
      puts "  search_demand_score=#{row['search_demand_score']} search_demand_breakdown=#{row['search_demand_breakdown'].to_json}"
      puts "  improvement_potential_score=#{row['improvement_potential_score']} improvement_potential_breakdown=#{row['improvement_potential_breakdown'].to_json}"
      puts [
        "  expected_improvement_score=#{row['expected_improvement_score']}",
        "formula=SearchDemand:#{formula['search_demand_score']} * ImprovementPotential:#{formula['improvement_potential_score']} * BusinessValue:#{formula['business_value']} * SuccessProbability:#{formula['success_probability']} / EstimatedWorkHours:#{formula['estimated_work_hours']}"
      ].join(" ")
    end
  end

  def print_article_opportunity_today_result(result)
    puts "mode=#{result.mode}"
    puts "business_id=#{result.business.id}"
    puts "business_name=#{result.business.name}"
    puts "latest_snapshot_at=#{result.latest_snapshot_at || '-'}"
    puts "analyzer_result_count=#{result.analyzer_result_count}"
    puts "analyzer_action_candidate_count=#{result.analyzer_action_candidate_count}"
    puts "today_eligible_count=#{result.today_eligible_count}"
    puts "duplicate_suppressed_count=#{result.duplicate_suppressed_count}"
    puts "archived_count=#{result.archived_count}"
    puts "status_excluded_count=#{result.status_excluded_count}"
    puts "fallback_used=#{result.fallback_used}"
    puts "activated_count=#{result.activated_count}"
    puts "today_top10:"
    if result.top10.empty?
      puts "-"
    else
      result.top10.each.with_index(1) do |row, index|
        puts [
          "rank=#{index}",
          "candidate_id=#{row.candidate_id}",
          "article_id=#{row.article_id || '-'}",
          "article_path=#{row.article_path || '-'}",
          "improvement_type=#{row.improvement_type_label}",
          "expected_improvement_score=#{row.expected_improvement_score.to_f.round(2)}",
          "search_demand_score=#{row.search_demand_score.to_f.round(2)}",
          "improvement_potential_score=#{row.improvement_potential_score.to_f.round(2)}",
          "success_probability=#{row.success_probability.to_f.round(2)}",
          "estimated_work_hours=#{row.estimated_work_hours.to_f.round(2)}",
          "status=#{row.status}",
          "generation_source=#{row.generation_source}",
          "today_exclusion_reason=#{row.today_exclusion_reason || '-'}"
        ].join(" ")
      end
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
