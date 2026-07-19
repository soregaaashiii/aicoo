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
        DiagnosticRow.new(
          item: entry.fetch(:item),
          classification: entry.fetch(:classification),
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
      score_entries(main_ranking_entries).sort_by { |entry| entry_sort_key(entry) }.map { |entry| entry.fetch(:item).with(score: entry.fetch(tab_score_key).round(2)) }
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
      revenue_scores = normalized_scores(entries) { |entry| revenue_raw_value(entry.fetch(:item), entry.fetch(:classification)) }
      learning_scores = normalized_scores(entries) { |entry| learning_raw_value(entry.fetch(:item), entry.fetch(:classification)) }

      entries.map.with_index do |entry, index|
        classification = entry.fetch(:classification)
        multiplier = classification.actionability_multiplier * classification.category_multiplier
        revenue = revenue_scores.fetch(index) * multiplier
        learning = learning_scores.fetch(index) * multiplier
        balanced = ((revenue_scores.fetch(index) * 0.6) + (learning_scores.fetch(index) * 0.4)) * multiplier
        entry.merge(
          normalized_value_score: selected_normalized_score(revenue, learning, balanced),
          tab_score_revenue: revenue,
          tab_score_learning: learning,
          tab_score_balanced: balanced
        )
      end
    end

    def normalized_scores(entries)
      values = entries.map { |entry| yield(entry).to_d }
      positive_values = values.select(&:positive?)
      max = positive_values.max
      return values.map { 0.to_d } if max.blank? || max.zero?

      values.map { |value| value.positive? ? ((value / max) * 100).round(4) : 0.to_d }
    end

    def revenue_raw_value(item, classification)
      return classification.raw_value if classification.raw_value_type == "expected_improvement_score"

      delta_value(item).to_d
    end

    def learning_raw_value(item, classification)
      return article_opportunity_metric(item, "improvement_potential_score") if classification.raw_value_type == "expected_improvement_score"
      return item.learning_score.to_d if item.respond_to?(:learning_score)

      confidence_value(item) * 100
    end

    def selected_normalized_score(revenue, learning, balanced)
      case mode
      when "learning"
        learning
      when "balanced"
        balanced
      else
        revenue
      end
    end

    def tab_score_key
      case mode
      when "learning"
        :tab_score_learning
      when "balanced"
        :tab_score_balanced
      else
        :tab_score_revenue
      end
    end

    def entry_sort_key(entry)
      item = entry.fetch(:item)
      classification = entry.fetch(:classification)
      [
        -entry.fetch(tab_score_key),
        -classification.raw_value,
        -confidence_value(item),
        -record_timestamp(item),
        -record_id(item)
      ]
    end

    def sort_key(item)
      if article_opportunity_item?(item)
        return [
          -article_opportunity_metric(item, "expected_improvement_score"),
          -article_opportunity_metric(item, "search_demand_score"),
          -article_opportunity_metric(item, "improvement_potential_score"),
          -article_opportunity_metric(item, "success_probability"),
          article_opportunity_metric(item, "estimated_work_hours"),
          -record_timestamp(item),
          -record_id(item)
        ]
      end

      [
        -delta_value(item),
        -confidence_value(item),
        -record_timestamp(item),
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
          delta_value(item),
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

    def confidence_value(item)
      return item.confidence.to_d if item.respond_to?(:confidence)

      item.respond_to?(:success_probability) ? item.success_probability.to_d : 0.to_d
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

    def record_id(item)
      record = item.respond_to?(:record) ? item.record : nil
      record&.try(:id).to_i
    end
  end
end
