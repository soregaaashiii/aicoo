require "test_helper"

module Aicoo
  class BusinessOwnedUrlPolicyTest < ActiveSupport::TestCase
    test "classifies suelog urls and paths as owner pages" do
      business = businesses(:suelog)
      business.update!(project_key: "suelog", repository_name: "suelog")

      https_result = BusinessOwnedUrlPolicy.call(business:, url: "https://suelog.jp/articles/suelog-comparison")
      path_result = BusinessOwnedUrlPolicy.call(business:, url: "/articles/suelog-comparison")

      assert https_result.owner_page?
      assert_equal "https://suelog.jp/articles/suelog-comparison", https_result.url
      assert path_result.owner_page?
      assert_equal "/articles/suelog-comparison", path_result.url
    end

    test "converts external pages to reference urls and falls back to owner page" do
      business = businesses(:suelog)
      business.update!(project_key: "suelog", repository_name: "suelog")

      result = BusinessOwnedUrlPolicy.call(
        business:,
        url: "https://s.tabelog.com/rstLst/cond13-00-01/"
      )

      assert result.owner_page?
      assert_equal "https://suelog.jp/", result.url
      assert_equal "https://s.tabelog.com/rstLst/cond13-00-01/", result.reference_url
      assert_equal "https://suelog.jp/", result.fallback_url
    end
  end
end
