require "test_helper"

module Aicoo
  class RequestQueryContextTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      DataSourceCostProfile.ensure_defaults!
    end

    test "reuses repeated configuration lookups within one read request" do
      sql = capture_sql do
        RequestQueryContext.within do
          2.times do
            DataSourceCostProfile.for_source("serp")
            ProxyScoreWeight.for_business(@business)
            BusinessDataSourceSetting.for_business_and_source(@business, "serp")
            AicooGoogleCredential.default
          end
        end
      end

      assert_operator matching_query_count(sql, "data_source_cost_profiles"), :<=, 1
      assert_operator matching_query_count(sql, "proxy_score_weights"), :<=, 1
      assert_operator matching_query_count(sql, "business_data_source_settings"), :<=, 1
      assert_operator matching_query_count(sql, "aicoo_google_credentials"), :<=, 1
    end

    test "reuses a generated fallback for a missing cost profile" do
      sql = capture_sql do
        RequestQueryContext.within do
          2.times { DataSourceCostProfile.for_source("unregistered_source") }
        end
      end

      assert_equal 1, matching_query_count(sql, "data_source_cost_profiles")
    end

    test "reuses revenue event availability and average within one read request" do
      sql = capture_sql do
        RequestQueryContext.within do
          2.times do
            RequestQueryContext.revenue_event_available(@business) { @business.revenue_events.revenue.exists? }
            RequestQueryContext.revenue_event_average_amount(@business) { @business.revenue_events.revenue.average(:amount) }
          end
        end
      end

      assert_operator matching_query_count(sql, "revenue_events"), :<=, 2
    end

    test "does not persist data source defaults while rendering a read request" do
      DataSourceCostProfile.stub(:ensure_defaults!, -> { flunk("read requests must not persist defaults") }) do
        RequestQueryContext.within { Aicoo::Serp::OptionalMode.call }
      end
    end

    test "keeps business connection result unchanged" do
      direct = BusinessConnectionStatus.new(@business, source_key: "serp").call
      contextual = RequestQueryContext.within do
        BusinessConnectionStatus.new(@business, source_key: "serp").call
      end

      assert_equal direct.to_h, contextual.to_h
    end

    test "keeps integration health result unchanged" do
      direct = BusinessIntegrationHealth.new(businesses: [ @business ]).call.business_healths.first
      contextual = RequestQueryContext.within do
        BusinessIntegrationHealth.new(businesses: [ @business ]).call.business_healths.first
      end

      assert_equal direct.to_h, contextual.to_h
    end

    test "reuses owner action candidates and businesses within one read request" do
      sql = capture_sql do
        RequestQueryContext.within do
          2.times do
            RequestQueryContext.owner_active_action_candidates
            RequestQueryContext.owner_active_action_candidates_by_business_id
            RequestQueryContext.owner_real_businesses
          end
        end
      end

      action_candidate_loads = sql.count do |statement|
        statement.match?(/\ASELECT "action_candidates"\.\* FROM "action_candidates"/)
      end
      business_loads = sql.count do |statement|
        statement.match?(/\ASELECT "businesses"\.\* FROM "businesses".*ORDER BY "businesses"\."name" ASC/)
      end

      assert_equal 1, action_candidate_loads
      assert_equal 1, business_loads
    end

    test "reuses normalized persisted metadata within one read request" do
      candidate = action_candidates(:nagazakicho_article)

      normalized = RequestQueryContext.within do
        first = RequestQueryContext.normalized_metadata(candidate)
        second = RequestQueryContext.normalized_metadata(candidate)

        assert_same first, second
        first
      end

      assert_equal candidate.metadata.to_h.deep_stringify_keys, normalized
    end

    test "normalizes changed metadata without mutating the record" do
      candidate = action_candidates(:nagazakicho_article)
      candidate.metadata = { purpose: { kind: "test" } }
      original = candidate.metadata.deep_dup

      normalized = RequestQueryContext.within do
        RequestQueryContext.normalized_metadata(candidate)
      end

      assert_equal({ "purpose" => { "kind" => "test" } }, normalized)
      assert_equal original, candidate.metadata
    end

    test "reuses running daily run rows across latest status modes" do
      sql = capture_sql do
        RequestQueryContext.within do
          DailyRunExecutionStatus.call(include_latest: false)
          DailyRunExecutionStatus.call(include_latest: true)
        end
      end

      running_queries = sql.count do |statement|
        statement.include?('FROM "aicoo_daily_runs" WHERE (') &&
          statement.include?('"aicoo_daily_runs"."status" =')
      end
      assert_equal 1, running_queries
    end

    private

    def capture_sql
      sql = []
      subscriber = lambda do |_name, _started, _finished, _id, payload|
        next if payload[:name].to_s.in?(%w[SCHEMA TRANSACTION])
        next unless payload[:sql].to_s.match?(/\ASELECT/i)

        sql << payload[:sql]
      end
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
      sql
    end

    def matching_query_count(sql, table_name)
      sql.count { |statement| statement.include?(%("#{table_name}")) }
    end
  end
end
