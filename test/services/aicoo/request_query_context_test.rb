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
