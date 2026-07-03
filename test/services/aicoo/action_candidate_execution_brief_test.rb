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
  end
end
