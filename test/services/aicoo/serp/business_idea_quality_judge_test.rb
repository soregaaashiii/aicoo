require "test_helper"

module Aicoo
  module Serp
    class BusinessIdeaQualityJudgeTest < ActiveSupport::TestCase
      test "accepts concrete service idea" do
        result = BusinessIdeaQualityJudge.call(
          source_query: "飲食店 代行 大阪",
          attributes: {
            "business_name" => "飲食店SNS運用代行サービス",
            "target_customer" => "大阪の飲食店の運営者・担当者",
            "problem" => "SNS集客を継続できず予約機会を逃している",
            "offering" => "SNS投稿と予約導線の初期運用代行",
            "revenue_model" => "初期相談と月額運用代行で収益化する",
            "validation_method" => "LPを作成し相談登録とCTAクリックを確認する",
            "product_type" => "lp"
          }
        )

        assert result.auto_publishable
        assert_equal "auto_publishable", result.status
        assert_empty result.missing_fields
      end

      test "rejects search query used as business name" do
        result = BusinessIdeaQualityJudge.call(
          source_query: "飲食店 代行 大阪",
          attributes: {
            "business_name" => "飲食店 代行 大阪の検証事業",
            "target_customer" => "大阪の飲食店の運営者・担当者",
            "problem" => "代行先を選べず集客機会を逃している",
            "offering" => "飲食店向け代行支援",
            "revenue_model" => "月額運用で収益化する",
            "validation_method" => "LPで相談登録を確認する",
            "product_type" => "lp"
          }
        )

        assert_not result.auto_publishable
        assert_equal "needs_edit", result.status
        assert_includes result.reasons.join, "検索クエリ"
      end

      test "rejects cta and description text as business name" do
        cta = BusinessIdeaQualityJudge.call(
          source_query: "飲食店 SNS",
          attributes: {
            "business_name" => "無料相談する",
            "target_customer" => "飲食店の運営者・担当者",
            "problem" => "SNS集客を継続できない",
            "offering" => "SNS運用代行サービス",
            "revenue_model" => "月額運用で収益化する",
            "validation_method" => "LPで相談登録を確認する",
            "product_type" => "lp"
          }
        )
        description = BusinessIdeaQualityJudge.call(
          source_query: "飲食店 SNS",
          attributes: {
            "business_name" => "飲食店向けにSNS集客を支援します。",
            "target_customer" => "飲食店の運営者・担当者",
            "problem" => "SNS集客を継続できない",
            "offering" => "SNS運用代行サービス",
            "revenue_model" => "月額運用で収益化する",
            "validation_method" => "LPで相談登録を確認する",
            "product_type" => "lp"
          }
        )

        assert_not cta.auto_publishable
        assert_not description.auto_publishable
        assert_includes cta.reasons.join, "CTA"
        assert_includes description.reasons.join, "説明文"
      end

      test "requires product type before auto publish" do
        result = BusinessIdeaQualityJudge.call(
          source_query: "飲食店 SNS",
          attributes: {
            "business_name" => "飲食店SNS運用代行サービス",
            "target_customer" => "大阪の飲食店の運営者・担当者",
            "problem" => "SNS集客を継続できず予約機会を逃している",
            "solution" => "SNS投稿と予約導線の初期運用代行",
            "monetization" => "初期相談と月額運用代行で収益化する",
            "validation_plan" => "LPを作成し相談登録とCTAクリックを確認する"
          }
        )

        assert_not result.auto_publishable
        assert_includes result.reasons.join, "LPかSaaS"
      end
    end
  end
end
