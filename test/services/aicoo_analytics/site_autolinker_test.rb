require "test_helper"

module AicooAnalytics
  class SiteAutolinkerTest < ActiveSupport::TestCase
    test "creates analytics site from business with site url" do
      business = Business.create!(name: "吸えログ")
      business.define_singleton_method(:site_url) { "https://suelog.jp" }

      result = SiteAutolinker.new.link!(business)

      site = AicooAnalyticsSite.find_by!(public_url: "https://suelog.jp")
      assert_equal 1, result.created_count
      assert_equal business, site.business
      assert_equal "suelog.jp", site.domain
      assert_equal "shared", site.authentication_mode
      assert site.auto_created?
    end

    test "creates analytics site from published landing page" do
      landing_page = create_published_landing_page

      result = SiteAutolinker.new(base_url: "https://aicoo.example.com").link!(landing_page)

      site = AicooAnalyticsSite.find_by!(public_url: "https://aicoo.example.com/lp/#{landing_page.published_slug}")
      assert_equal 1, result.created_count
      assert_equal landing_page.headline, site.name
      assert_equal "aicoo.example.com", site.domain
      assert_equal "shared", site.authentication_mode
      assert site.auto_created?
    end

    test "skips landing page when public url cannot be generated" do
      landing_page = create_landing_page

      result = SiteAutolinker.new(base_url: nil).link!(landing_page)

      assert_equal 0, result.created_count
      assert_equal 1, result.skipped_count
      assert_includes result.warnings.join, "公開URL未設定"
    end

    test "does not create duplicate analytics site" do
      landing_page = create_published_landing_page
      autolinker = SiteAutolinker.new(base_url: "https://aicoo.example.com")

      assert_difference("AicooAnalyticsSite.count", 1) do
        autolinker.link!(landing_page)
      end
      assert_no_difference("AicooAnalyticsSite.count") do
        autolinker.link!(landing_page)
      end
    end

    private

    def create_landing_page
      experiment = AicooLabExperiment.create!(
        title: "Autolink LP",
        experiment_type: "lp",
        acquisition_channel: "sns",
        status: "preview_ready",
        approval_status: "approved"
      )
      experiment.create_aicoo_lab_landing_page!(
        headline: "Autolink headline",
        subheadline: "Sub",
        body: "Body",
        cta_text: "登録する",
        status: "preview_ready"
      )
    end

    def create_published_landing_page
      create_landing_page.tap(&:publish!)
    end
  end
end
