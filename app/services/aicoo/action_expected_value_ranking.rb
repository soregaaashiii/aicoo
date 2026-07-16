module Aicoo
  class ActionExpectedValueRanking
    DEFAULT_PER_PAGE = 20

    Result = Data.define(
      :items,
      :total_count,
      :current_page,
      :total_pages,
      :per_page,
      :offset
    )

    def initialize(items:, mode:, page: nil, per_page: DEFAULT_PER_PAGE)
      @items = items
      @mode = mode.to_s.presence || "revenue"
      @current_page = [ page.to_i, 1 ].max
      @per_page = [ per_page.to_i, DEFAULT_PER_PAGE ].select(&:positive?).first || DEFAULT_PER_PAGE
    end

    def call
      Aicoo::MemoryDiagnostics.measure("Aicoo::ActionExpectedValueRanking#call", context: memory_context) do
        ranked = items.reject { |item| excluded_item?(item) }
                      .then { |filtered| deduplicate_action_items(filtered) }
                      .sort_by { |item| sort_key(item) }
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

    def sort_key(item)
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
