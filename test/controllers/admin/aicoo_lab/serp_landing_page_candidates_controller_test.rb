require "test_helper"

module Admin
  module AicooLab
    class SerpLandingPageCandidatesControllerTest < ActionDispatch::IntegrationTest
      test "index shows serp research form and candidate list" do
        get admin_aicoo_lab_serp_landing_page_candidates_url

        assert_response :success
        assert_includes response.body, "SERPからLP候補生成"
        assert_includes response.body, "SERP調査してLP候補を生成"
      end

      test "creates serp analysis and landing page candidates from pasted results" do
        business = Business.create!(name: "SERP LP Business")

        assert_difference -> { SerpAnalysis.count }, 1 do
          assert_difference -> { SerpLandingPageCandidate.count }, 3 do
            post admin_aicoo_lab_serp_landing_page_candidates_url, params: {
              serp_research: {
                business_id: business.id,
                keyword: "梅田 喫煙 カフェ",
                location: "Osaka",
                device: "desktop",
                raw_text: serp_text
              }
            }
          end
        end

        assert_redirected_to admin_aicoo_lab_serp_landing_page_candidates_url
        candidate = SerpLandingPageCandidate.order(:created_at).last
        assert_equal "梅田 喫煙 カフェ", candidate.keyword
        assert candidate.lp_title.present?
        assert candidate.target_audience.present?
        assert candidate.problem.present?
        assert candidate.lp_description.present?
        assert candidate.cta_text.present?
        assert candidate.competition_note.include?("競合強度")
      end

      test "creates draft public landing page from serp candidate and publishes into public surfaces" do
        candidate = SerpLandingPageCandidate.create!(
          keyword: "難波 喫煙 居酒屋",
          service_name: "難波 喫煙 居酒屋 比較ガイド",
          target_audience: "難波で喫煙できる居酒屋を探す人",
          problem: "喫煙可否が分かりにくく、店選びに時間がかかる。",
          lp_title: "難波で喫煙できる居酒屋を探す",
          lp_description: "難波の喫煙可能な居酒屋選びを短時間で整理します。",
          cta_text: "店舗リストを見る",
          expected_value_score: 72,
          competition_note: "競合強度: 40/100"
        )

        assert_difference([ "AicooLabExperiment.count", "AicooLabLandingPage.count" ], 1) do
          post admin_aicoo_lab_serp_landing_page_candidate_create_landing_page_url(candidate)
        end

        landing_page = candidate.reload.aicoo_lab_landing_page
        assert_redirected_to admin_aicoo_lab_edit_public_landing_page_url(landing_page)
        assert_equal "converted", candidate.status
        assert_equal "draft", landing_page.public_status
        assert_equal "難波で喫煙できる居酒屋を探す", landing_page.headline

        get public_landing_pages_url
        assert_response :success
        assert_not_includes response.body, landing_page.headline

        patch admin_aicoo_lab_publish_public_landing_page_url(landing_page)
        landing_page.reload

        assert_equal "published", landing_page.public_status

        get root_url
        assert_response :success
        assert_includes response.body, landing_page.headline

        get public_landing_pages_url
        assert_response :success
        assert_includes response.body, landing_page.headline

        get sitemap_url(format: :xml)
        assert_response :success
        assert_includes response.body, public_lp_path(landing_page.published_slug)
      end

      private

      def serp_text
        <<~TEXT
          梅田の喫煙カフェまとめ,https://example.com/umeda-smoking-cafe,梅田で喫煙できるカフェ一覧
          大阪喫煙所ガイド,https://guide.example.com/osaka-smoking,大阪の喫煙所情報
          梅田カフェ比較,https://competitor.example.com/umeda-cafe,梅田のカフェ比較
        TEXT
      end
    end
  end
end
