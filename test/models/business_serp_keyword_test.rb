require "test_helper"

class BusinessSerpKeywordTest < ActiveSupport::TestCase
  test "normalizes keyword and prevents duplicates per business" do
    business = businesses(:suelog)
    business.business_serp_keywords.create!(keyword: "梅田  喫煙", source: "manual", status: "active")

    duplicate = business.business_serp_keywords.build(keyword: "梅田 喫煙", source: "manual", status: "active")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:normalized_keyword], "has already been taken"
  end

  test "parses newline and comma separated keywords" do
    keywords = BusinessSerpKeyword.parse_keywords("梅田 喫煙\n難波 喫煙,大阪 喫煙 居酒屋、梅田 喫煙")

    assert_equal [ "梅田 喫煙", "難波 喫煙", "大阪 喫煙 居酒屋" ], keywords
  end

  test "status transitions keep excluded reason" do
    keyword = businesses(:suelog).business_serp_keywords.create!(keyword: "大阪 喫煙", source: "manual", status: "active")

    keyword.exclude!(reason: "対象外")

    assert_equal "excluded", keyword.status
    assert_equal "対象外", keyword.reason
    assert keyword.metadata_json["excluded_at"].present?
  end
end
