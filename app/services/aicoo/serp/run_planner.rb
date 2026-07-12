module Aicoo
  module Serp
    class RunPlanner
      Row = Data.define(:business, :status, :reason)

      def initialize(max_total_queries:, force: false)
        @max_total_queries = max_total_queries.to_i
        @force = force
      end

      def rows
        @rows ||= [ Row.new(market_exploration_business, "run", "new_business_exploration") ]
      end

      def run_rows
        rows.select { |row| row.status == "run" }
      end

      def skipped_rows
        rows.reject { |row| row.status == "run" }
      end

      def run_query_ids
        []
      end

      def metadata
        {
          "plan" => {
            "run_count" => run_rows.size,
            "skip_count" => skipped_rows.size,
            "max_total_queries" => max_total_queries,
            "force" => force,
            "rows" => rows.map do |row|
              {
                "business_id" => row.business.id,
                "business_name" => row.business.name,
                "status" => row.status,
                "reason" => row.reason
              }
            end
          }
        }
      end

      private

      attr_reader :max_total_queries, :force

      def market_exploration_business
        Business.find_or_initialize_by(name: "AICOO Market Exploration") do |business|
          business.description = "SERP新規事業探索の保存用システムBusiness"
          business.status = "launched"
          business.lifecycle_stage = "idea"
          business.business_type = "exploration"
          business.source = "system"
          business.created_by_aicoo = true
          business.resource_status = "archived"
        end
      end

    end
  end
end
