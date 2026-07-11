require "test_helper"

module Aicoo
  module CandidateGenerators
    class SuelogGeneratorTest < ActiveSupport::TestCase
      FakeArticle = Struct.new(:id, :slug, :title, :seo_title, :meta_description, :summary, :recommended_areas, keyword_init: true) do
        def searchable_text
          [ title, seo_title, meta_description, summary, recommended_areas, slug ].compact.join(" ").downcase
        end
      end

      setup do
        @business = businesses(:suelog)
        @business.update!(project_key: "suelog", repository_name: "suelog")
      end

      test "skips safely when SUELOG_DATABASE_URL is missing" do
        without_suelog_database_url do
          result = SuelogGenerator.call(business: @business)

          assert_equal 0, result.created_count
          assert_includes result.skipped, "missing_database_url"
          assert result.health.warning?
        end
      end

      test "does not run for non suelog business" do
        result = SuelogGenerator.call(business: businesses(:cards))

        assert_equal 0, result.created_count
        assert_includes result.skipped, "not_suelog_business"
      end

      test "detects duplicate candidates by external source record and query" do
        ActionCandidate.create!(
          business: @business,
          title: "duplicate",
          action_type: "article_create",
          status: "idea",
          generation_source: "suelog_db",
          metadata: {
            "external_source" => "suelog_db",
            "external_record_id" => "query:abc",
            "target_query" => "梅田 喫煙 カフェ"
          }
        )

        generator = SuelogGenerator.new(business: @business)

        assert generator.send(
          :duplicate_candidate?,
          action_type: "article_create",
          external_record_id: "query:abc",
          target_query: "梅田 喫煙 カフェ"
        )
      end

      test "landing page article slug maps to article update" do
        generator = SuelogGenerator.new(business: @business)
        article = FakeArticle.new(
          id: 1,
          slug: "umeda-smoking-cafe",
          title: "梅田で喫煙できるカフェ",
          seo_title: nil,
          meta_description: nil,
          summary: nil,
          recommended_areas: "梅田"
        )

        matched = generator.send(
          :article_for,
          row: { query: "梅田 喫煙 カフェ", landing_page: "https://suelog.jp/articles/umeda-smoking-cafe" },
          articles: [ article ]
        )

        assert_equal article, matched
      end

      test "missing article remains nil so generator creates article_create instead of seo_improvement" do
        generator = SuelogGenerator.new(business: @business)

        matched = generator.send(
          :article_for,
          row: { query: "曽根崎 喫煙 バー", landing_page: "https://suelog.jp/shops/123" },
          articles: []
        )

        assert_nil matched
      end

      private

      def without_suelog_database_url
        original = ENV["SUELOG_DATABASE_URL"]
        ENV.delete("SUELOG_DATABASE_URL")
        yield
      ensure
        ENV["SUELOG_DATABASE_URL"] = original if original
      end
    end
  end
end
