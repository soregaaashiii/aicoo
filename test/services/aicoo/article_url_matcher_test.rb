require "test_helper"

module Aicoo
  class ArticleUrlMatcherTest < ActiveSupport::TestCase
    Article = Struct.new(:id, :slug, :canonical_url, :title, keyword_init: true) do
      def public_path
        "/articles/#{slug}"
      end
    end

    setup do
      @articles = [
        Article.new(id: 1, slug: "umeda-smoking-cafe", canonical_url: "https://suelog.jp/articles/umeda-smoking-cafe", title: "梅田 喫煙 カフェ"),
        Article.new(id: 2, slug: "namba-smoking-izakaya", canonical_url: "https://suelog.jp/articles/namba-smoking-izakaya", title: "難波 喫煙 居酒屋")
      ]
      @matcher = ArticleUrlMatcher.new(articles: @articles)
    end

    test "matches canonical URL" do
      result = @matcher.match("https://www.suelog.jp/articles/umeda-smoking-cafe/?utm_source=ga4")

      assert_equal 1, result.article_id
      assert_equal "canonical", result.match_type
      assert_operator result.confidence, :>, 0.9
    end

    test "matches normalized path" do
      result = @matcher.match("/articles/NAMBA-Smoking-Izakaya/?utm_source=ga4")

      assert_equal 2, result.article_id
      assert_equal "normalized", result.match_type
      assert_equal "/articles/namba-smoking-izakaya", result.matched_path
    end

    test "matches slug" do
      result = @matcher.match("umeda-smoking-cafe")

      assert_equal 1, result.article_id
      assert_equal "slug", result.match_type
    end

    test "matches page title even when it is not a URL" do
      result = @matcher.match("梅田 喫煙 カフェ | 吸えログ")

      assert_equal 1, result.article_id
      assert_equal "partial", result.match_type
    end

    test "returns none for unmatched page" do
      result = @matcher.match("/articles/not-found")

      assert_nil result.article_id
      assert_equal "none", result.match_type
      assert_equal "no_article_match", result.reason
    end
  end
end
