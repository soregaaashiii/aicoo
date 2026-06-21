require "test_helper"

class SerpAnalysisImportServiceTest < ActiveSupport::TestCase
  test "creates serp analysis results and data import" do
    business = businesses(:suelog)
    raw_text = <<~TEXT
      中崎町の喫煙所まとめ	https://example.com/nakazakicho	喫煙所一覧
      食べログ 中崎町 喫煙可	https://tabelog.com/osaka/A2701/A270101/	飲食店
      Google Maps	https://google.com/maps	地図
    TEXT

    assert_difference -> { SerpAnalysis.count }, 1 do
      assert_difference -> { SerpResult.count }, 3 do
        assert_difference -> { DataImport.count }, 1 do
          result = SerpAnalysisImportService.new(
            business,
            keyword: "中崎町 喫煙所",
            raw_text:,
            filename: "serp.txt",
            location: "Osaka",
            device: "mobile"
          ).call

          assert_equal "serp", result.data_import.data_source.source_type
          assert_equal "中崎町 喫煙所", result.serp_analysis.keyword
          assert_equal 3, result.serp_analysis.result_count
          assert_operator result.serp_analysis.competition_score, :>, 0
          assert_includes result.data_import.processed_text, "competition_score"
        end
      end
    end
  end
end
