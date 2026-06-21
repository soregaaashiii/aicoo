require "test_helper"

class SerpAnalysesControllerTest < ActionDispatch::IntegrationTest
  test "creates serp analysis from manual text" do
    assert_difference -> { SerpAnalysis.count }, 1 do
      post business_serp_analyses_url(businesses(:suelog)), params: {
        serp_analysis: {
          keyword: "中崎町 喫煙所",
          location: "Osaka",
          device: "desktop",
          raw_text: "Title\thttps://example.com\tSnippet"
        }
      }
    end

    assert_redirected_to business_url(businesses(:suelog))
  end
end
