require "test_helper"

module Aicoo
  class ActionCandidateExecutionBriefTest < ActiveSupport::TestCase
    test "builds executable before after brief from action candidate metadata" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "吸えログのCV導線を改善する",
        description: "クリックはあるが送客導線が弱い。",
        action_type: "ui_improvement",
        status: "pending",
        generation_source: "serp",
        immediate_value_yen: 42_000,
        expected_hours: 0.5,
        success_probability: 0.5,
        metadata: {
          "source_query" => "大阪 喫煙 カフェ",
          "target_url" => "/osaka/smoking-cafe",
          "admin_url" => "/admin/articles/12",
          "edit_url" => "/admin/articles/12/edit",
          "resource_type" => "Article",
          "resource_name" => "大阪喫煙カフェ記事",
          "current_title" => "大阪の喫煙カフェ",
          "proposed_title" => "【2026年版】大阪で喫煙できるカフェ比較｜吸えログ",
          "current_meta_description" => "大阪の喫煙カフェを紹介します。",
          "proposed_meta_description" => "大阪で喫煙できるカフェを料金・口コミ・エリア別に比較できます。",
          "current_cta" => "詳細を見る",
          "proposed_cta" => "近くの喫煙カフェを今すぐ確認する",
          "serp_common_words" => [ "比較", "口コミ" ],
          "serp_common_structure" => [ "比較表", "FAQ" ],
          "missing_elements" => [ "料金", "掲載件数" ],
          "serp_top_results" => [
            { "position" => 1, "title" => "大阪 喫煙カフェ 比較", "url" => "https://example.com", "snippet" => "比較できます" }
          ],
          "target_files" => [ "app/views/articles/show.html.erb" ],
          "completion_criteria" => [ "タイトル変更済み", "CTA変更済み" ]
        }
      )

      brief = ActionCandidateExecutionBrief.new(candidate)

      assert_equal "Article", brief.target[:resource_type]
      assert_equal "/admin/articles/12/edit", brief.target[:edit_url]
      assert_equal "【2026年版】大阪で喫煙できるカフェ比較｜吸えログ", brief.before_after_items.first[:after]
      assert_equal [ "比較", "口コミ" ], brief.serp_comparison[:common_words]
      assert_equal [ "料金", "掲載件数" ], brief.serp_comparison[:missing_elements]
      assert_equal [ "app/views/articles/show.html.erb" ], brief.file_changes
      assert_equal [ "タイトル変更済み", "CTA変更済み" ], brief.completion_criteria
      assert_includes brief.prompt_markdown, "現在: 大阪の喫煙カフェ"
      assert_includes brief.prompt_markdown, "変更後: 【2026年版】大阪で喫煙できるカフェ比較｜吸えログ"
      assert_includes brief.prompt_markdown, "大阪 喫煙 カフェ"
      assert_equal "吸えログ", brief.openai_context.dig(:business, "name")
    end

    test "hides metric-derived pseudo target url and shows candidate pages" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "吸えログのCV導線を改善する",
        description: "clicksはある一方でphone/map/affiliate_clicksが少ないため、送客に近い導線を改善します。",
        action_type: "ui_improvement",
        status: "pending",
        generation_source: "ai_business",
        immediate_value_yen: 42_000,
        expected_hours: 0.5,
        success_probability: 0.5,
        metadata: {
          "target_url" => "/map/affiliate_clicks",
          "candidate_pages" => [ "店舗詳細ページ", "地図ページ", "記事内店舗カード" ],
          "source_metric" => "affiliate_clicks"
        }
      )

      brief = ActionCandidateExecutionBrief.new(candidate)

      assert_equal "未特定", brief.target[:url]
      assert_equal [ "店舗詳細ページ", "地図ページ", "記事内店舗カード" ], brief.target[:candidate_pages]
      assert_empty brief.open_links.select { |link| link[:url] == "/map/affiliate_clicks" }
      assert_no_match(/URL: \/map\/affiliate_clicks/, brief.prompt_markdown)
    end

    test "does not use unrelated serp results for suelog branded query" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "吸えログの指名検索対策ページを作る",
        description: "吸えログ 比較のSERPに無関係なログ管理記事が混ざっています。",
        action_type: "seo_article",
        status: "pending",
        generation_source: "serp",
        immediate_value_yen: 18_000,
        expected_hours: 2,
        success_probability: 0.36,
        metadata: {
          "source_query" => "吸えログ 比較",
          "serp_top_results" => [
            { "position" => 1, "title" => "ログ管理システム比較", "url" => "https://example.com/log", "snippet" => "操作ログと監査ログの比較" },
            { "position" => 2, "title" => "勤怠ログ管理ツール比較", "url" => "https://example.com/time-log", "snippet" => "業務日報とログ管理" },
            { "position" => 3, "title" => "大阪 喫煙可能 カフェ", "url" => "https://example.com/smoking-cafe", "snippet" => "梅田で喫煙可のカフェを探す" }
          ]
        }
      )

      brief = ActionCandidateExecutionBrief.new(candidate)

      assert_equal [ "大阪 喫煙可能 カフェ" ], brief.top_serp_results.map { |row| row["title"] }
      assert_equal "指名検索ページ不足", brief.serp_comparison.dig(:relevance, :status)
      assert_equal "suelog-comparison", brief.new_article_spec[:slug]
      assert_equal "/articles/suelog-comparison", brief.target[:url]
      assert_equal "/admin/articles/new?slug=suelog-comparison", brief.target[:admin_url]
      assert_equal "新規作成", brief.article_id
      assert_equal "新規記事", brief.page_change_type
      assert_includes brief.own_site_gap, "食べログ/Googleマップ/Rettyとの違い"
      assert_includes brief.before_after_items.first[:after], "吸えログとは？"
      assert_includes brief.prompt_markdown, "SERP関連度"
      assert_includes brief.prompt_markdown, "推奨slug: suelog-comparison"
      assert_includes brief.prompt_markdown, "URL: /articles/suelog-comparison"
      assert_includes brief.prompt_markdown, "H2 食べログ・Googleマップ・Rettyとの違い"
      assert_includes brief.prompt_markdown, "サービス / 喫煙情報 / 紙タバコ/加熱式"
      assert_includes brief.prompt_markdown, "指名検索対策ページ"
      assert_includes brief.prompt_markdown, "大阪で喫煙できる店探し"
      assert_includes brief.completion_criteria, "/articles/suelog-comparison が存在すること"
      assert_no_match(/- 1位 ログ管理システム比較/, brief.prompt_markdown)
    end
  end
end
