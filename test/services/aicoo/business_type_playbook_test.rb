require "test_helper"

module Aicoo
  class BusinessTypePlaybookTest < ActiveSupport::TestCase
    test "seo media forbids public LP creation" do
      business = businesses(:suelog)
      decision = business.business_type_playbook.call(
        title: "吸えログの公開LPを作成する",
        action_type: "build_lp",
        description: "LPを用意します"
      )

      assert decision.forbidden
      assert_not decision.allowed
      assert_match(/SEOメディア/, decision.reason)
    end

    test "seo media prefers seo improvement" do
      business = businesses(:suelog)
      decision = business.business_type_playbook.call(
        title: "吸えログのタイトル改善",
        action_type: "seo_improvement",
        description: "CTRを改善します"
      )

      assert decision.allowed
      assert decision.preferred
      assert_equal "seo_media", decision.metadata.fetch("business_type")
    end

    test "saas allows feature development" do
      business = businesses(:cards)
      decision = business.business_type_playbook.call(
        title: "オンボーディング機能を追加する",
        action_type: "feature_development"
      )

      assert decision.allowed
      assert decision.preferred
    end
  end
end
