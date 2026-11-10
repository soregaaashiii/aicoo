require "test_helper"

class BusinessServiceTest < ActiveSupport::TestCase
  test "requires valid status" do
    service = BusinessService.new(business: businesses(:suelog), name: "Test", status: "unknown")

    assert_not service.valid?
  end

  test "reference pages do not replace the user page" do
    service = BusinessService.new(
      business: businesses(:suelog),
      name: "Reference pages",
      status: "live",
      url: "https://service.example.com",
      admin_url: "https://service.example.com/admin",
      other_url: "https://status.example.com"
    )

    assert_equal "https://service.example.com", service.display_url
    assert_equal "https://service.example.com/admin", service.metadata["admin_url"]
    assert_equal "https://status.example.com", service.metadata["other_url"]
  end

  test "user page remains the default analysis target and reference pages require opt in" do
    service = BusinessService.new(
      business: businesses(:suelog),
      name: "Analysis pages",
      status: "live",
      url: "https://service.example.com",
      admin_url: "https://service.example.com/admin",
      other_url: "https://status.example.com",
      admin_page_analysis_enabled: true
    )

    assert service.page_analysis_enabled?("user")
    assert service.page_analysis_enabled?("admin")
    assert_not service.page_analysis_enabled?("other")
    assert_equal [
      "https://service.example.com",
      "https://service.example.com/admin"
    ], service.analysis_target_urls
  end

  test "pages without urls are never analysis targets" do
    service = BusinessService.new(
      business: businesses(:suelog),
      name: "Missing pages",
      status: "live",
      user_page_analysis_enabled: true,
      admin_page_analysis_enabled: true,
      other_page_analysis_enabled: true
    )

    assert_empty service.analysis_target_pages
  end

  test "named additional pages are listed with the registered user page" do
    service = BusinessService.new(
      business: businesses(:suelog),
      name: "Named pages",
      status: "live",
      url: "https://service.example.com",
      metadata: {
        "additional_pages" => [
          {
            "id" => "help-page",
            "name" => "ヘルプ",
            "url" => "https://service.example.com/help",
            "analysis_enabled" => true
          },
          {
            "id" => "recruit-page",
            "name" => "採用情報",
            "url" => "https://service.example.com/jobs",
            "analysis_enabled" => false
          }
        ]
      }
    )

    assert_equal "https://service.example.com", service.user_page_configuration[:url]
    assert_equal %w[ヘルプ 採用情報], service.additional_page_configurations.pluck(:name)
    assert_equal [
      "https://service.example.com",
      "https://service.example.com/help"
    ], service.analysis_target_urls
  end

  test "legacy admin and other urls remain visible as named additional pages" do
    service = BusinessService.new(
      business: businesses(:suelog),
      name: "Legacy pages",
      status: "live",
      url: "https://service.example.com",
      admin_url: "https://service.example.com/admin",
      other_url: "https://status.example.com",
      other_page_name: "稼働状況"
    )

    assert_equal [ "管理者ページ", "稼働状況" ], service.additional_page_configurations.pluck(:name)
    assert_equal [ "admin", "other" ], service.additional_page_configurations.pluck(:id)
  end
end
