require "test_helper"

module Aicoo
  class DataSourcePolicyTest < ActiveSupport::TestCase
    test "existing business improvement uses only internal trusted sources by default" do
      business = businesses(:suelog)
      business.update!(business_type: "seo_media")

      policy = DataSourcePolicy.for(business)

      assert policy.enabled?(:ga4)
      assert policy.enabled?(:gsc)
      assert policy.enabled?(:internal)
      refute policy.enabled?(:serp)
      refute policy.enabled?(:reddit)
      refute policy.enabled?(:x)
      refute policy.enabled?(:news)
      assert_equal %w[ga4 gsc internal], policy.used_source_states.map(&:key)
    end

    test "exploration business can use external sources for new business exploration" do
      business = businesses(:cards)
      business.update!(business_type: "exploration")

      policy = DataSourcePolicy.for(business)

      assert policy.enabled?(:serp, context: :new_business_exploration)
      assert policy.enabled?(:reddit, context: :new_business_exploration)
      assert policy.enabled?(:x, context: :new_business_exploration)
      assert policy.enabled?(:news, context: :new_business_exploration)
    end

    test "external source can be enabled for existing improvement only with explicit verified policy" do
      business = businesses(:cards)
      business.update!(business_type: "saas")
      business.business_data_source_settings.create!(
        source_key: "serp",
        enabled: true,
        connection_status: "linked",
        metadata: { "analysis_policy" => { "allow_existing_business_improvement" => true } }
      )

      policy = DataSourcePolicy.for(business)

      assert policy.enabled?(:serp, context: :existing_business_improvement)
    end
  end
end
