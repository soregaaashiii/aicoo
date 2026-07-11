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
      ranked = items.sort_by { |item| sort_key(item) }
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

    private

    attr_reader :items, :mode, :current_page, :per_page

    def sort_key(item)
      [
        -item.expected_value_yen.to_i,
        -item.score.to_d,
        priority_rank(item),
        item.business_name.to_s,
        item.stable_id.to_s
      ]
    end

    def priority_rank(item)
      case item.priority
      when "critical" then 0
      when "high" then 1
      when "improvement" then 3
      when "new_business" then 4
      else 5
      end
    end
  end
end
