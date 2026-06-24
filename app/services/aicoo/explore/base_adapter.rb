module Aicoo
  module Explore
    class BaseAdapter
      Result = Data.define(:created_count, :skipped_count, :message)

      def initialize(data_source)
        @data_source = data_source
      end

      def sync
        Result.new(created_count: 0, skipped_count: 0, message: "Adapter structure only. API sync is not implemented yet.")
      end

      private

      attr_reader :data_source
    end
  end
end
