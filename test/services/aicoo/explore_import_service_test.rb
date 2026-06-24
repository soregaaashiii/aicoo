require "test_helper"

module Aicoo
  class ExploreImportServiceTest < ActiveSupport::TestCase
    test "imports csv observations and creates import log" do
      raw_text = <<~CSV
        title,description,score
        シーシャ需要増加,検索量増加,80
      CSV

      assert_difference("ExploreObservation.count", 1) do
        assert_difference("ExploreImportLog.count", 1) do
          result = ExploreImportService.run!(source_type: "google_trends", format: "csv", raw_text:)

          assert_empty result.errors
          assert_equal 1, result.imported_count
        end
      end

      observation = ExploreObservation.last
      assert_equal "シーシャ需要増加", observation.title
      assert_equal "検索量増加", observation.description
      assert_equal 80, observation.score.to_i
      assert_equal "google_trends", observation.explore_data_source.source_type
      assert_equal "csv", ExploreImportLog.last.import_format
    end

    test "imports json observations" do
      raw_text = <<~JSON
        [
          { "title": "AI副業需要", "description": "急増中", "score": 90 }
        ]
      JSON

      result = ExploreImportService.run!(source_type: "reddit", format: "json", raw_text:)

      assert_empty result.errors
      assert_equal 1, result.imported_count
      assert_equal "AI副業需要", ExploreObservation.last.title
      assert_equal "reddit", ExploreObservation.last.explore_data_source.source_type
    end

    test "imports text observations with defaults" do
      result = ExploreImportService.run!(
        source_type: "youtube",
        format: "text",
        raw_text: "喫煙カフェ需要増加\nAI店舗分析"
      )

      assert_empty result.errors
      assert_equal 2, result.imported_count
      assert_equal [ "喫煙カフェ需要増加", "AI店舗分析" ], ExploreObservation.order(:id).last(2).map(&:title)
      assert_equal 50, ExploreObservation.last.score.to_i
      assert_equal "opportunity", ExploreObservation.last.observation_type
    end

    test "preview does not persist observations" do
      assert_no_difference("ExploreObservation.count") do
        result = ExploreImportService.preview(source_type: "x", format: "text", raw_text: "SNSで話題")

        assert_equal 1, result.observations.size
        assert_equal "SNSで話題", result.observations.first.title
      end
    end

    test "invalid input returns errors" do
      result = ExploreImportService.run!(source_type: "unknown", format: "csv", raw_text: "")

      assert_includes result.errors, "source_type is invalid"
      assert_includes result.errors, "raw_text is blank"
      assert_equal 0, result.imported_count
    end
  end
end
