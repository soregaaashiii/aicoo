require "test_helper"

module Aicoo
  module LpIntegration
    class LandingPagePagePathAssignerTest < ActiveSupport::TestCase
      setup do
        @business = Business.create!(
          name: "Page Path Business",
          status: "launched",
          business_type: "landing_page"
        )
        @campaign = @business.business_campaigns.create!(
          name: "SEO",
          campaign_type: "seo",
          status: "active"
        )
      end

      test "keeps an existing page path unchanged" do
        landing_page = create_landing_page(
          repository: "https://github.com/example/ignored",
          metadata: { "ga4_page_path" => "/existing/path" }
        )

        result = LandingPagePagePathAssigner.new(landing_page:).call

        assert_equal "/existing/path", result.page_path
        assert_equal false, result.generated
        assert_equal "/existing/path", landing_page.reload.landing_page_ga4_path
      end

      test "uses landing page slug before business slug and repository name" do
        @business.update!(metadata: @business.metadata.to_h.merge("slug" => "business-slug"))
        landing_page = create_landing_page(
          repository: "https://github.com/example/repository-name",
          metadata: { "slug" => "Landing_Page Slug" }
        )

        result = LandingPagePagePathAssigner.new(landing_page:).call

        assert_equal "/landing_page-slug", result.page_path
        assert_equal :landing_page_slug, result.source
        assert_equal result.page_path, landing_page.reload.landing_page_ga4_path
      end

      test "uses business slug then repository name then business id" do
        @business.update!(metadata: @business.metadata.to_h.merge("slug" => "business-slug"))
        business_slug_page = create_landing_page(repository: "https://github.com/example/repository-name")
        assert_equal "/business-slug", LandingPagePagePathAssigner.new(landing_page: business_slug_page).call.page_path

        @business.update!(metadata: @business.metadata.to_h.except("slug"))
        repository_page = create_landing_page(repository: "https://github.com/example/voice-analysis-pro")
        assert_equal "/voice-analysis-pro", LandingPagePagePathAssigner.new(landing_page: repository_page).call.page_path

        fallback_page = create_landing_page(repository: nil)
        assert_equal "/business-#{@business.id}", LandingPagePagePathAssigner.new(landing_page: fallback_page).call.page_path
      end

      test "adds a numeric suffix when another landing page already uses the path" do
        create_landing_page(
          repository: "https://github.com/example/voice-analysis-pro",
          metadata: { "ga4_page_path" => "/voice-analysis-pro" }
        )
        landing_page = create_landing_page(repository: "https://github.com/example/voice-analysis-pro")

        result = LandingPagePagePathAssigner.new(landing_page:).call

        assert_equal "/voice-analysis-pro-2", result.page_path
        assert_match LandingPagePagePathAssigner::GENERATED_PATH_PATTERN, result.page_path
      end

      private

      def create_landing_page(repository:, metadata: {})
        @business.business_prototypes.create!(
          business_campaign: @campaign,
          name: "LP",
          prototype_type: repository.present? ? "github" : "other",
          location: repository.presence || "手動指定（未設定）",
          status: "active",
          metadata: {
            "role" => BusinessPrototype::EXTERNAL_LANDING_PAGE_ROLE,
            "lp_name" => "LP",
            "lp_repository_url" => repository,
            "lp_branch" => "main",
            "lp_public_status" => "testing"
          }.merge(metadata).compact
        )
      end
    end
  end
end
