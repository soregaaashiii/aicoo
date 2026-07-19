module Aicoo
  class ActionExpectedValueRanking
    DEFAULT_PER_PAGE = 20
    ARTICLE_OPPORTUNITY_MODEL_NAME = "article_opportunity_analyzer_snapshot_v1".freeze

    Result = Data.define(
      :items,
      :total_count,
      :current_page,
      :total_pages,
      :per_page,
      :offset
    )
    DiagnosticRow = Data.define(
      :item,
      :classification,
      :total_expected_value_yen,
      :revenue_expected_value_yen,
      :traffic_expected_value_yen,
      :conversion_expected_value_yen,
      :learning_expected_value_yen,
      :future_expected_value_yen,
      :strategic_expected_value_yen,
      :execution_cost_yen,
      :risk_cost_yen,
      :opportunity_cost_yen,
      :ranking_source,
      :expected_improvement,
      :non_yen_metric_used_for_ranking,
      :normalized_value_score,
      :tab_score_revenue,
      :tab_score_learning,
      :tab_score_balanced
    )

    def initialize(items:, mode:, page: nil, per_page: DEFAULT_PER_PAGE)
      @items = items
      @mode = mode.to_s.presence || "revenue"
      @current_page = [ page.to_i, 1 ].max
      @per_page = [ per_page.to_i, DEFAULT_PER_PAGE ].select(&:positive?).first || DEFAULT_PER_PAGE
    end

    def call
      Aicoo::MemoryDiagnostics.measure("Aicoo::ActionExpectedValueRanking#call", context: memory_context) do
        ranked = ranked_items
        total_count = ranked.size
        offset = (current_page - 1) * per_page
        page_items = ranked.slice(offset, per_page).to_a
        page_items = page_items.map.with_index(offset + 1) { |item, rank| item.with(rank:) }

        Result.new(
          items: page_items,
          total_count:,
          current_page:,
          total_pages: [ (total_count.to_f / per_page).ceil, 1 ].max,
          per_page:,
          offset:
        )
      end
    end

    def diagnostic_rows
      entries = classified_entries
      scored = score_entries(entries)
      scored.map do |entry|
        breakdown = entry.fetch(:expected_value_breakdown)
        DiagnosticRow.new(
          item: entry.fetch(:item),
          classification: entry.fetch(:classification),
          total_expected_value_yen: breakdown.fetch(:total_expected_value_yen),
          revenue_expected_value_yen: breakdown.fetch(:revenue_expected_value_yen),
          traffic_expected_value_yen: breakdown.fetch(:traffic_expected_value_yen),
          conversion_expected_value_yen: breakdown.fetch(:conversion_expected_value_yen),
          learning_expected_value_yen: breakdown.fetch(:learning_expected_value_yen),
          future_expected_value_yen: breakdown.fetch(:future_expected_value_yen),
          strategic_expected_value_yen: breakdown.fetch(:strategic_expected_value_yen),
          execution_cost_yen: breakdown.fetch(:execution_cost_yen),
          risk_cost_yen: breakdown.fetch(:risk_cost_yen),
          opportunity_cost_yen: breakdown.fetch(:opportunity_cost_yen),
          ranking_source: breakdown.fetch(:ranking_source),
          expected_improvement: breakdown.fetch(:expected_improvement),
          non_yen_metric_used_for_ranking: false,
          normalized_value_score: entry.fetch(:normalized_value_score),
          tab_score_revenue: entry.fetch(:tab_score_revenue),
          tab_score_learning: entry.fetch(:tab_score_learning),
          tab_score_balanced: entry.fetch(:tab_score_balanced)
        )
      end
    end

    private

    attr_reader :items, :mode, :current_page, :per_page

    def memory_context
      {
        mode:,
        input_count: items.size,
        current_page:,
        per_page:
      }
    end

    def ranked_items
      score_entries(main_ranking_entries).sort_by { |entry| entry_sort_key(entry) }.map do |entry|
        entry.fetch(:item).with(score: entry.fetch(:expected_value_breakdown).fetch(:total_expected_value_yen).round(2))
      end
    end

    def main_ranking_entries
      entries = classified_entries
      main = entries.select { |entry| entry.fetch(:classification).included_in_main_ranking }
      return main if main.present?

      entries.select { |entry| entry.fetch(:classification).candidate_category == "fallback" }
             .sort_by { |entry| -entry.fetch(:classification).raw_value }
             .first(1)
    end

    def classified_entries
      @classified_entries ||= items.reject { |item| excluded_item?(item) }
                                   .then { |filtered| deduplicate_action_items(filtered) }
                                   .map { |item| { item:, classification: Aicoo::TodayRankingClassifier.call(item) } }
    end

    def score_entries(entries)
      entries.map do |entry|
        breakdown = expected_value_breakdown(entry.fetch(:item))
        total = breakdown.fetch(:total_expected_value_yen)
        entry.merge(
          expected_value_breakdown: breakdown,
          normalized_value_score: total,
          tab_score_revenue: total,
          tab_score_learning: total,
          tab_score_balanced: total
        )
      end
    end

    def entry_sort_key(entry)
      item = entry.fetch(:item)
      breakdown = entry.fetch(:expected_value_breakdown)
      [
        -breakdown.fetch(:total_expected_value_yen),
        -confidence_value(item),
        estimated_work_hours(item),
        record_created_timestamp(item),
        -record_id(item)
      ]
    end

    def excluded_item?(item)
      return true if item.respond_to?(:valuation_status) && item.valuation_status.to_s == "unvalued"

      record = item.respond_to?(:record) ? item.record : nil
      return false unless record.is_a?(ActionCandidate)
      return true if record.status.to_s.in?(ActionCandidate::INACTIVE_STATUSES)

      metadata = record.metadata.to_h
      return true if metadata["url_classification"].to_s.in?(%w[external_reference invalid])
      return true if metadata["target_url_type"].to_s.in?(%w[external_reference invalid])
      return true if Aicoo::ActionCandidateRankingGuard.rejection_reason(record).present?
      return true if metadata["repair_reason"].present? && metadata["rejection_reason"].present?
      return true if metadata["ranking_cleanup_status"].to_s.in?(%w[resolved superseded rejected_duplicate rejected_irrelevant])
      return false unless record.action_type.to_s.in?(%w[seo_improvement article_update])

      metadata["target_url_type"].to_s == "proposed_new"
    end

    def deduplicate_action_items(filtered)
      passthrough = []
      grouped = Hash.new { |hash, key| hash[key] = [] }

      filtered.each do |item|
        record = item.respond_to?(:record) ? item.record : nil
        if record.is_a?(ActionCandidate)
          grouped[action_dedupe_key(record)] << item
        else
          passthrough << item
        end
      end

      passthrough + grouped.values.map { |group| representative_item(group) }
    end

    def representative_item(group)
      group.max_by do |item|
        [
          article_opportunity_item?(item) ? 1 : 0,
          total_expected_value_yen(item),
          confidence_value(item),
          record_timestamp(item),
          record_id(item)
        ]
      end
    end

    def action_dedupe_key(record)
      metadata = record.metadata.to_h.deep_stringify_keys
      [
        record.business_id,
        normalized_action_type(record),
        normalized_query(metadata, record),
        normalize(metadata["planned_url"].presence || metadata["proposed_url"].presence || metadata["recommended_url"].presence || metadata["recommended_slug"].presence),
        normalize(metadata["content_type"].presence || metadata["work_type"].presence || record.action_type)
      ].join("::")
    end

    def normalized_action_type(record)
      type = record.action_type.to_s
      return "article_create" if type.in?(%w[new_article_candidate article_create seo_article])

      type
    end

    def normalized_query(metadata, record)
      normalize(
        metadata["target_keyword"].presence ||
          metadata["target_query"].presence ||
          metadata["source_query"].presence ||
          metadata["query"].presence ||
          metadata["search_query"].presence ||
          metadata.dig("evidence", "query").presence ||
          metadata.dig("article_candidate", "search_query").presence ||
          record.title
      )
    end

    def normalize(value)
      value.to_s.unicode_normalize(:nfkc).downcase.gsub(/[[:space:]　]+/, " ").strip
    end

    def delta_value(item)
      return item.action_expected_value_delta_yen.to_i if item.respond_to?(:action_expected_value_delta_yen)

      item.expected_value_yen.to_i
    end

    def expected_value_breakdown(item)
      record = item.respond_to?(:record) ? item.record : nil
      metadata = record.is_a?(ActionCandidate) ? record.metadata.to_h.deep_stringify_keys : {}
      total = total_expected_value_yen(item)
      execution_cost = item.respond_to?(:execution_cost_yen) ? item.execution_cost_yen.to_d : 0.to_d
      learning = record.is_a?(ActionCandidate) ? record.expected_learning_value_yen.to_d : 0.to_d
      expected_profit_model = metadata["expected_profit_model"].to_h
      ranking_source = article_opportunity_item?(item) ? Aicoo::ArticleOpportunityExpectedProfit::MODEL_NAME : "total_expected_value_yen"

      {
        total_expected_value_yen: total,
        revenue_expected_value_yen: total,
        traffic_expected_value_yen: decimal_metadata(metadata, "traffic_expected_value_yen"),
        conversion_expected_value_yen: decimal_metadata(metadata, "conversion_expected_value_yen"),
        learning_expected_value_yen: learning,
        future_expected_value_yen: decimal_metadata(metadata, "future_expected_value_yen"),
        strategic_expected_value_yen: decimal_metadata(metadata, "strategic_expected_value_yen"),
        execution_cost_yen: execution_cost,
        risk_cost_yen: decimal_metadata(metadata, "risk_cost_yen"),
        opportunity_cost_yen: decimal_metadata(metadata, "opportunity_cost_yen"),
        ranking_source:,
        expected_improvement: expected_profit_model["expected_improvement_score"].presence || article_opportunity_metric(item, "expected_improvement_score")
      }
    end

    def total_expected_value_yen(item)
      delta_value(item).to_d
    end

    def decimal_metadata(metadata, key)
      metadata[key].to_s.delete(",").to_d
    end

    def confidence_value(item)
      return item.confidence.to_d if item.respond_to?(:confidence)

      item.respond_to?(:success_probability) ? item.success_probability.to_d : 0.to_d
    end

    def estimated_work_hours(item)
      return item.expected_hours.to_d if item.respond_to?(:expected_hours)

      0.to_d
    end

    def article_opportunity_item?(item)
      record = item.respond_to?(:record) ? item.record : nil
      return false unless record.is_a?(ActionCandidate)

      metadata = record.metadata.to_h
      metadata["value_model_name"].to_s == ARTICLE_OPPORTUNITY_MODEL_NAME &&
        metadata["analysis_source"].to_s == "article_analytics_snapshot" &&
        metadata["snapshot_id"].present? &&
        metadata["expected_improvement_score"].present?
    end

    def article_opportunity_metric(item, key)
      record = item.respond_to?(:record) ? item.record : nil
      record&.metadata.to_h[key].to_s.delete(",").to_d
    end

    def record_timestamp(item)
      record = item.respond_to?(:record) ? item.record : nil
      timestamp = record&.try(:updated_at) || record&.try(:created_at) || Time.zone.at(0)
      timestamp.to_i
    end

    def record_created_timestamp(item)
      record = item.respond_to?(:record) ? item.record : nil
      timestamp = record&.try(:created_at) || Time.zone.at(0)
      timestamp.to_i
    end

    def record_id(item)
      record = item.respond_to?(:record) ? item.record : nil
      record&.try(:id).to_i
    end
  end
end
