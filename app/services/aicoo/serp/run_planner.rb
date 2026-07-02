module Aicoo
  module Serp
    class RunPlanner
      Row = Data.define(:business, :serp_query, :status, :reason)

      def initialize(target_businesses:, max_total_queries:, force: false, single_serp_query: nil)
        @target_businesses = Array(target_businesses)
        @max_total_queries = max_total_queries.to_i
        @force = force
        @single_serp_query = single_serp_query
      end

      def rows
        @rows ||= begin
          return [ Row.new(single_serp_query.business, single_serp_query, "run", "single_query_force") ] if single_serp_query

          selected_count = 0
          target_businesses.flat_map do |business|
            business.serp_queries.by_priority.map do |serp_query|
              status, reason = status_for(serp_query, selected_count)
              selected_count += 1 if status == "run"
              Row.new(business, serp_query, status, reason)
            end
          end
        end
      end

      def run_rows
        rows.select { |row| row.status == "run" }
      end

      def skipped_rows
        rows.reject { |row| row.status == "run" }
      end

      def run_query_ids
        run_rows.map { |row| row.serp_query.id }
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
                "serp_query_id" => row.serp_query.id,
                "query" => row.serp_query.query,
                "status" => row.status,
                "reason" => row.reason
              }
            end
          }
        }
      end

      private

      attr_reader :target_businesses, :max_total_queries, :force, :single_serp_query

      def status_for(serp_query, selected_count)
        return [ "skip", "paused" ] if serp_query.status == "paused"
        return [ "skip", "archived" ] if serp_query.status == "archived"
        return [ "skip", "disabled" ] unless serp_query.enabled?
        return [ "run", "force" ] if force && within_limit?(selected_count)
        return [ "skip", "daily_limit_reached" ] if serp_query.daily_limit.to_i <= 0 || serp_query.today_run_count >= serp_query.daily_limit.to_i
        return [ "skip", "recently_fetched_24h" ] if serp_query.recently_successful?
        return [ "skip", "global_daily_limit" ] unless within_limit?(selected_count)

        [ "run", "priority_selected" ]
      end

      def within_limit?(selected_count)
        return true if max_total_queries <= 0

        selected_count < max_total_queries
      end
    end
  end
end
