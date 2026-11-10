module Aicoo
  class BusinessListOrder
    POSITION_KEY = "business_list_position".freeze
    DIRECTIONS = {
      "up" => -1,
      "down" => 1
    }.freeze

    class << self
      def sort(businesses)
        Array(businesses).sort_by do |business|
          position = position_for(business)
          [ position.nil? ? 1 : 0, position || 0, business.name.to_s.downcase, business.id ]
        end
      end

      def move(business, direction:)
        offset = DIRECTIONS[direction.to_s]
        return false unless offset

        moved = false
        Business.transaction do
          businesses = sort(Business.real_businesses.lock.order(:name).to_a)
          current_index = businesses.index { |row| row.id == business.id }
          target_index = current_index && current_index + offset
          next unless current_index && target_index&.between?(0, businesses.length - 1)

          businesses[current_index], businesses[target_index] = businesses[target_index], businesses[current_index]
          persist_positions(businesses)
          moved = true
        end
        moved
      end

      def position_for(business)
        value = business.metadata.to_h[POSITION_KEY]
        position = Integer(value, exception: false)
        position if position && position >= 0
      end

      private

      def persist_positions(businesses)
        businesses.each_with_index do |business, position|
          next if position_for(business) == position

          metadata = business.metadata.to_h.merge(POSITION_KEY => position)
          business.update_columns(metadata:)
          business.metadata = metadata
        end
      end
    end
  end
end
