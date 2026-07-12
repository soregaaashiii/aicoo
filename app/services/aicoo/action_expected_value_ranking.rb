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
        ranked = items.reject { |item| item.respond_to?(:valuation_status) && item.valuation_status.to_s == "unvalued" }
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
