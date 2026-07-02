require "test_helper"

module Aicoo
  module Serp
    class KeywordManagerTest < ActiveSupport::TestCase
      test "adds manual keywords and reports excluded duplicates" do
        business = businesses(:suelog)
        excluded = business.business_serp_keywords.create!(keyword: "除外 KW", source: "manual", status: "excluded")

        result = KeywordManager.add_manual_keywords!(
          business:,
          raw_keywords: "梅田 喫煙\n除外 KW"
        )

        assert_equal [ "梅田 喫煙" ], result.added.map(&:keyword)
        assert_equal [ excluded ], result.excluded
        assert business.business_serp_keywords.exists?(keyword: "梅田 喫煙", status: "active", source: "manual")
      end

      test "generates pending suggestions without readding excluded keywords" do
        business = businesses(:suelog)
        business.business_serp_keywords.create!(keyword: business.name, source: "manual", status: "excluded")

        suggestions = KeywordManager.generate_suggestions!(business:)

        assert suggestions.any?
        assert suggestions.all? { |keyword| keyword.status == "pending" }
        assert_not business.business_serp_keywords.where(keyword: business.name, status: "pending").exists?
      end
    end
  end
end
