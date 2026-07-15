require "test_helper"

module Aicoo
  class BusinessOwnedUrlPolicyTest < ActiveSupport::TestCase
    test "classifies suelog root as own existing and article paths as proposed when not verified" do
      business = businesses(:suelog)
      business.update!(project_key: "suelog", repository_name: "suelog")

      root_result = BusinessOwnedUrlPolicy.call(business:, url: "https://suelog.jp/")
      article_result = BusinessOwnedUrlPolicy.call(business:, url: "/articles/suelog-comparison")

      assert root_result.owner_page?
      assert_equal "own_existing", root_result.url_classification
      assert article_result.proposed_new?
      assert_equal "proposed_new", article_result.url_classification
      assert_equal "/articles/suelog-comparison", article_result.url
    end

    test "classifies external pages as references without owner fallback target" do
      business = businesses(:suelog)
      business.update!(project_key: "suelog", repository_name: "suelog")

      result = BusinessOwnedUrlPolicy.call(
        business:,
        url: "https://s.tabelog.com/rstLst/cond13-00-01/"
      )

      assert result.external_reference?
      assert_nil result.url
      assert_equal "https://s.tabelog.com/rstLst/cond13-00-01/", result.reference_url
      assert_equal "https://suelog.jp/", result.fallback_url
    end

    test "classifies it trend and invalid article slug" do
      business = businesses(:suelog)

      it_trend = BusinessOwnedUrlPolicy.call(business:, url: "https://it-trend.jp/log_management/article/84-0008")
      broken = BusinessOwnedUrlPolicy.call(business:, url: "/articles/-smoking")
      placeholder = BusinessOwnedUrlPolicy.call(business:, url: "/articles/article-1234")

      assert it_trend.external_reference?
      assert broken.invalid?
      assert placeholder.invalid?
    end
  end
end
