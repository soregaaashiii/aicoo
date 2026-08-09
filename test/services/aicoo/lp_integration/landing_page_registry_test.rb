require "test_helper"

module Aicoo
  module LpIntegration
    class LandingPageRegistryTest < ActiveSupport::TestCase
      setup do
        @business = Business.create!(
          name: "既存LP登録テスト事業",
          status: "launched",
          business_type: "landing_page"
        )
        @registry = LandingPageRegistry.new(business: @business)
      end

      test "registers an existing landing page with only a public url" do
        landing_page = @registry.register_existing!(
          name: " 公開済みLP ",
          url: " HTTPS://Example.COM/service/ "
        )

        assert_equal @business, landing_page.business
        assert landing_page.external_landing_page?
        assert_equal "公開済みLP", landing_page.landing_page_name
        assert_equal "https://example.com/service", landing_page.landing_page_url
        assert_nil landing_page.landing_page_repository_url
        assert_equal "published", landing_page.landing_page_public_status
        assert_equal "existing_external", landing_page.metadata["registration_source"]
        assert landing_page.metadata["registered_at"].present?
      end

      test "registers and normalizes an optional github repository url" do
        landing_page = @registry.register_existing!(
          name: "GitHub LP",
          url: "https://example.com/github-lp",
          repository_url: " https://github.com/Example/Marketing-LP.git/ "
        )

        assert_equal "https://github.com/example/marketing-lp", landing_page.landing_page_repository_url
      end

      test "registers a github repository without requiring a public url" do
        landing_page = @registry.register_existing!(
          name: "Repository LP",
          repository_url: " https://github.com/Example/Repository-LP.git/ "
        )

        assert_equal "github", landing_page.prototype_type
        assert_equal "https://github.com/example/repository-lp", landing_page.location
        assert_equal "https://github.com/example/repository-lp", landing_page.landing_page_repository_url
        assert_nil landing_page.landing_page_url
        assert_equal "testing", landing_page.landing_page_public_status
        assert_equal "公開準備中", landing_page.landing_page_public_status_label
        assert_equal "existing_external", landing_page.metadata["registration_source"]
      end

      test "requires either a github repository or a public url" do
        error = assert_raises(ActiveRecord::RecordInvalid) do
          @registry.register_existing!(name: "取得元なし")
        end

        assert_includes error.record.errors[:repository_url], "または公開URLを入力してください。"
        assert_empty @business.business_prototypes.external_landing_pages
      end

      test "rejects an invalid public url" do
        error = assert_raises(ActiveRecord::RecordInvalid) do
          @registry.register_existing!(name: "不正URL", url: "javascript:alert(1)")
        end

        assert_includes error.record.errors[:location], "はhttpまたはhttpsの正しいURLを入力してください。"
        assert_empty @business.business_prototypes.external_landing_pages
      end

      test "requires a landing page name" do
        error = assert_raises(ActiveRecord::RecordInvalid) do
          @registry.register_existing!(name: " ", url: "https://example.com/lp")
        end

        assert_includes error.record.errors[:name], "を入力してください。"
        assert_empty @business.business_prototypes.external_landing_pages
      end

      test "rejects an invalid github repository url" do
        error = assert_raises(ActiveRecord::RecordInvalid) do
          @registry.register_existing!(
            name: "不正GitHub",
            url: "https://example.com/lp",
            repository_url: "https://github.com/example/repository/issues"
          )
        end

        assert_includes error.record.errors[:repository_url], "はGitHubリポジトリURLを入力してください。"
      end

      test "rejects a duplicate normalized public url within the business" do
        @registry.register_existing!(name: "先のLP", url: "https://example.com/lp/")

        error = assert_raises(ActiveRecord::RecordInvalid) do
          @registry.register_existing!(name: "後のLP", url: "https://EXAMPLE.com/lp#overview")
        end

        assert_includes error.record.errors[:location], "はこの事業に登録済みです。"
        assert_equal 1, @business.business_prototypes.external_landing_pages.count
      end

      test "rejects a duplicate normalized github repository within the business" do
        @registry.register_existing!(
          name: "先のLP",
          repository_url: "https://github.com/example/repository"
        )

        error = assert_raises(ActiveRecord::RecordInvalid) do
          @registry.register_existing!(
            name: "後のLP",
            repository_url: "https://github.com/EXAMPLE/REPOSITORY.git"
          )
        end

        assert_includes error.record.errors[:repository_url], "はこの事業に登録済みです。"
      end

      test "shows a publication failure for a registered repository without changing its stored public status" do
        landing_page = @registry.register_existing!(
          name: "失敗LP",
          repository_url: "https://github.com/example/failed-lp"
        )
        landing_page.update!(metadata: landing_page.metadata.to_h.merge("sync_status" => "failed"))

        assert_equal "testing", landing_page.landing_page_public_status
        assert_equal "公開失敗", landing_page.landing_page_public_status_label
      end

      test "allows the same public url in a different business" do
        other_business = Business.create!(name: "別事業", status: "launched", business_type: "saas")
        @registry.register_existing!(name: "LP A", url: "https://example.com/shared")

        assert_difference("other_business.business_prototypes.external_landing_pages.count", 1) do
          LandingPageRegistry.new(business: other_business).register_existing!(
            name: "LP B",
            url: "https://example.com/shared"
          )
        end
      end
    end
  end
end
