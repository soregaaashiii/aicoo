require "test_helper"

class ActionCandidateTest < ActiveSupport::TestCase
  test "calculates expected profit hourly value roi and final score before save" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "吸えログで電話確認を外注する",
      action_type: "outsourcing",
      immediate_value_yen: 50_000,
      success_probability: 0.6,
      expected_hours: 2,
      cost_yen: 10_000,
      strategic_value_score: 50,
      risk_reduction_score: 30,
      confidence_score: 80,
      priority_score: 60,
      status: "pending"
    )

    assert_equal 30_000, action_candidate.expected_profit_yen
    assert_equal 15_000, action_candidate.expected_hourly_value_yen
    assert_equal 3.to_d, action_candidate.roi
    assert_equal "11800.0", action_candidate.metadata.dig("strategic_learning", "base_score")
    assert action_candidate.final_score.positive?
    assert action_candidate.metadata.dig("strategic_learning", "strategic_score").present?
  end

  test "moves external target urls to competitor references for business improvements" do
    business = businesses(:suelog)
    business.update!(project_key: "suelog", repository_name: "suelog")

    action_candidate = ActionCandidate.create!(
      business:,
      title: "吸えログ 比較の不足要素を吸えログへ取り入れる",
      action_type: "seo_improvement",
      generation_source: "business_analyzer",
      immediate_value_yen: 18_000,
      success_probability: 0.4,
      expected_hours: 1.5,
      metadata: {
        "target_url" => "https://it-trend.jp/log_management/article/84-0008",
        "action_plan" => {
          "target" => "https://it-trend.jp/log_management/article/84-0008",
          "summary" => "吸えログ 比較の比較表とFAQを吸えログへ追加する"
        },
        "evidence" => {
          "page_path" => "https://it-trend.jp/log_management/article/84-0008",
          "query" => "吸えログ 比較"
        },
        "serp_top_results" => [
          { "title" => "ログ管理システム比較", "url" => "https://it-trend.jp/log_management/article/84-0008" }
        ],
        "serp_common_structure" => [ "比較表", "FAQ" ],
        "missing_elements" => [ "検索条件リンク" ]
      }
    )

    metadata = action_candidate.reload.metadata
    assert_nil metadata["target_url"]
    assert_nil metadata.dig("action_plan", "target")
    assert_nil metadata.dig("evidence", "page_path")
    assert_equal "external_reference", metadata["target_url_type"]
    assert_equal "external_reference", metadata["url_classification"]
    assert_equal "自社対象ページ未特定", metadata["target_url_warning"]
    assert_includes metadata["competitor_urls"], "https://it-trend.jp/log_management/article/84-0008"
    assert_includes metadata["competitor_features"], "比較表"
    assert_includes metadata["missing_features"], "検索条件リンク"
    assert_equal "external_url_moved_to_competitor_urls", metadata["invalid_target_url_reason"]
  end

  test "does not use tabelog url as suelog target url" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "喫煙可能な飲食店検索サービスのtitle/metaを改善する",
      action_type: "seo_improvement",
      generation_source: "business_analyzer",
      immediate_value_yen: 18_000,
      success_probability: 0.4,
      expected_hours: 1.5,
      metadata: {
        "target_url" => "https://s.tabelog.com/rstLst/cond13-00-01/",
        "source_query" => "喫煙可能な飲食店検索サービス"
      }
    )

    metadata = action_candidate.reload.metadata
    assert_nil metadata["target_url"]
    assert_equal "external_reference", metadata["target_url_type"]
    assert_equal "external_reference", metadata["url_classification"]
    assert_includes metadata["reference_urls"], "https://s.tabelog.com/rstLst/cond13-00-01/"
    assert_includes metadata["competitor_urls"], "https://s.tabelog.com/rstLst/cond13-00-01/"
  end

  test "stores external url as reference and planned url for new article candidates" do
    business = businesses(:suelog)

    action_candidate = ActionCandidate.create!(
      business:,
      title: "吸えログ比較記事を作成する",
      action_type: "new_article_candidate",
      generation_source: "business_analyzer",
      immediate_value_yen: 12_000,
      success_probability: 0.5,
      expected_hours: 1.5,
      metadata: {
        "target_url" => "https://it-trend.jp/log_management/article/84-0008",
        "recommended_slug" => "suelog-comparison",
        "action_plan" => {
          "target" => "https://it-trend.jp/log_management/article/84-0008"
        }
      }
    )

    metadata = action_candidate.reload.metadata
    assert_nil metadata["target_url"]
    assert_equal "/articles/suelog-comparison", metadata["planned_url"]
    assert_equal "proposed_new", metadata["planned_url_type"]
    assert_equal "proposed_new", metadata["url_classification"]
    assert_includes metadata["reference_urls"], "https://it-trend.jp/log_management/article/84-0008"
    assert_includes metadata["competitor_urls"], "https://it-trend.jp/log_management/article/84-0008"
    assert_equal "/articles/suelog-comparison", metadata.dig("action_plan", "target")
  end

  test "does not overwrite suelog db seo article value with generic seo model" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "「東通り 居酒屋 喫煙可」向けの記事を作成する",
      action_type: "article_create",
      generation_source: "suelog_db",
      immediate_value_yen: 12_345,
      success_probability: 0.1,
      expected_hours: 1.5,
      metadata: {
        "custom_marker" => "kept",
        "created_by" => "Aicoo::CandidateGenerators::SuelogGenerator",
        "target_query" => "東通り 居酒屋 喫煙可"
      }
    )

    action_candidate.reload
    assert_equal 12_345, action_candidate.expected_profit_yen
    assert_equal 12_345, action_candidate.expected_revenue_value_yen
    assert_equal 12_345, action_candidate.expected_total_value_yen
    assert_equal 12_345, action_candidate.final_expected_value_yen
    assert_equal true, action_candidate.metadata["seo_expected_value_skipped"]
    assert_equal "suelog_generated", action_candidate.metadata["skip_reason"]
    assert_equal "suelog_db", action_candidate.metadata["generation_source"]
    assert_equal "kept", action_candidate.metadata["custom_marker"]
  end

  test "does not overwrite suelog site insights business analyzer value with generic seo model" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "「梅田 喫煙 カフェ」向けの新規記事候補を作成する",
      action_type: "new_article_candidate",
      generation_source: "business_analyzer",
      immediate_value_yen: 34_000,
      success_probability: 0.2,
      expected_hours: 2,
      metadata: {
        "custom_marker" => "kept",
        "suelog_site_insights" => true,
        "query" => "梅田 喫煙 カフェ"
      }
    )

    action_candidate.reload
    assert_equal 34_000, action_candidate.expected_profit_yen
    assert_equal 34_000, action_candidate.final_expected_value_yen
    assert_equal true, action_candidate.metadata["seo_expected_value_skipped"]
    assert_equal "suelog_generated", action_candidate.metadata["skip_reason"]
    assert_equal "business_analyzer", action_candidate.metadata["generation_source"]
    assert_equal "kept", action_candidate.metadata["custom_marker"]
  end

  test "generic seo article candidates still use SeoArticleExpectedValue" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "通常SEO記事候補",
      action_type: "new_article_candidate",
      generation_source: "manual",
      immediate_value_yen: 99_999,
      success_probability: 0.5,
      expected_hours: 1,
      metadata: {
        "impressions" => 10_000,
        "current_ctr" => 0.01,
        "target_ctr" => 0.03,
        "conversion_rate" => 0.02,
        "profit_per_conversion" => 1_000
      }
    )

    action_candidate.reload
    assert_equal 2_000, action_candidate.expected_profit_yen
    assert_equal 2_000, action_candidate.final_expected_value_yen
    assert_nil action_candidate.metadata["seo_expected_value_skipped"]
    assert_equal Aicoo::SeoArticleExpectedValue::CALCULATION_VERSION, action_candidate.metadata.dig("seo_article_value_model", "calculation_version")
  end

  test "marks broken article path as invalid target" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "壊れた記事URLを改善する",
      action_type: "seo_improvement",
      generation_source: "business_analyzer",
      immediate_value_yen: 18_000,
      success_probability: 0.4,
      expected_hours: 1.5,
      metadata: {
        "target_url" => "/articles/-smoking"
      }
    )

    metadata = action_candidate.reload.metadata
    assert_nil metadata["target_url"]
    assert_equal "invalid", metadata["target_url_type"]
    assert_equal "invalid", metadata["url_classification"]
  end

  test "strategic philosophy changes final score" do
    setting = AicooSetting.current
    setting.update!(
      long_term_profit_weight: 45,
      short_term_profit_weight: 25,
      learning_weight: 15,
      automation_weight: 10,
      exploration_weight: 5
    )
    learning_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "学習データを増やす",
      action_type: "data_preparation",
      immediate_value_yen: 1_000,
      success_probability: 0.5,
      expected_hours: 1
    )
    baseline_score = learning_candidate.final_score

    setting.update!(
      long_term_profit_weight: 0,
      short_term_profit_weight: 0,
      learning_weight: 100,
      automation_weight: 0,
      exploration_weight: 0
    )
    learning_candidate.update!(title: "学習データを増やす updated")

    assert_operator learning_candidate.reload.final_score, :>, baseline_score
  end

  test "zero strategic weights do not break scoring" do
    AicooSetting.current.update!(
      long_term_profit_weight: 0,
      short_term_profit_weight: 0,
      learning_weight: 0,
      automation_weight: 0,
      exploration_weight: 0
    )

    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "Weight zero candidate",
      action_type: "other",
      immediate_value_yen: 10_000,
      success_probability: 0.5
    )

    assert action_candidate.final_score >= 0
    assert_equal "50.0", action_candidate.metadata.dig("strategic_learning", "strategic_score")
    assert action_candidate.metadata.dig("strategic_learning_guardrail", "base_score").present?
  end

  test "stores practicality metadata and adjusts score" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "CTR2%未満の記事5本をタイトル改訂する",
      action_type: "seo_improvement",
      immediate_value_yen: 20_000,
      success_probability: 0.5,
      expected_hours: 2,
      execution_prompt: "CTR2%未満の記事5本を選び、タイトルを改訂して公開してください。完了条件: 5本公開。"
    )

    assert action_candidate.practicality_score.present?
    assert action_candidate.metadata.dig("practicality", "subscores").present?
    assert action_candidate.metadata.dig("practicality", "multiplier").present?
  end

  test "stores business playbook score metadata" do
    BusinessPlaybook.create!(
      business: businesses(:suelog),
      sample_count: 20,
      confidence_score: 80,
      action_type_summary: {
        "seo_improvement" => {
          "type" => "seo_improvement",
          "score" => "80",
          "sample_count" => 20
        }
      }
    )
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "Playbook score candidate",
      action_type: "seo_improvement",
      immediate_value_yen: 20_000,
      success_probability: 0.5,
      expected_hours: 2
    )

    assert_equal 80.to_d, action_candidate.business_playbook_score
    assert action_candidate.metadata.dig("business_playbook", "coefficient").present?
    assert action_candidate.metadata.dig("business_playbook", "reason").present?
  end

  test "leaves hourly value and roi blank when denominators are blank or zero" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:cards),
      title: "新規事業候補のSERP調査をする",
      immediate_value_yen: 20_000,
      success_probability: 0.5,
      expected_hours: 0,
      cost_yen: 0
    )

    assert_equal 10_000, action_candidate.expected_profit_yen
    assert_nil action_candidate.expected_hourly_value_yen
    assert_nil action_candidate.roi
  end

  test "validates score ranges and success probability" do
    action_candidate = ActionCandidate.new(
      business: businesses(:suelog),
      title: "Invalid estimate",
      success_probability: 1.2,
      strategic_value_score: 101,
      risk_reduction_score: -1,
      confidence_score: 101,
      priority_score: -1
    )

    assert_not action_candidate.valid?
  end

  test "allows evaluation tuning action type" do
    action_candidate = ActionCandidate.new(
      business: businesses(:suelog),
      title: "Revenue評価式を見直す",
      action_type: "evaluation_tuning",
      success_probability: 0.5
    )

    assert action_candidate.valid?
  end

  test "auto classifies department when department is not specified" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "GSC分析でCTR改善を行う",
      action_type: "other",
      immediate_value_yen: 10_000,
      success_probability: 0.5
    )

    assert_equal "revenue", action_candidate.department
  end

  test "does not overwrite explicitly assigned department" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "GSC分析でCTR改善を行う",
      action_type: "other",
      department: "lab",
      immediate_value_yen: 10_000,
      success_probability: 0.5
    )

    assert_equal "lab", action_candidate.department
  end

  test "auto classifies seo ctr and gsc candidates as revenue" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "SEO記事のCTRをGSCで改善する",
      action_type: "other",
      immediate_value_yen: 10_000,
      success_probability: 0.5
    )

    assert_equal "revenue", action_candidate.department
  end

  test "auto classifies experiment validation and lp test candidates as lab" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "LPテストで仮説検証を行う",
      action_type: "other",
      immediate_value_yen: 10_000,
      success_probability: 0.5
    )

    assert_equal "lab", action_candidate.department
  end

  test "auto classifies new business mvp and market research candidates as new business" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:cards),
      title: "新規事業のMVP作成前に市場調査を行う",
      action_type: "other",
      immediate_value_yen: 10_000,
      success_probability: 0.5
    )

    assert_equal "new_business", action_candidate.department
  end

  test "keeps unclear candidates as general" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:cards),
      title: "管理方針を整理する",
      action_type: "other",
      immediate_value_yen: 10_000,
      success_probability: 0.5
    )

    assert_equal "general", action_candidate.department
  end

  test "applies execution feasibility correction before score calculation" do
    business = businesses(:suelog)
    seed_candidate = ActionCandidate.create!(
      business:,
      title: "SEO改善seed",
      action_type: "seo_improvement",
      immediate_value_yen: 10_000,
      success_probability: 0.5,
      expected_hours: 1
    )
    3.times do
      ActionExecutionLog.create!(
        action_candidate: seed_candidate,
        business:,
        planned_action: "500件実行",
        planned_quantity: 500,
        actual_action: "250件実行",
        actual_quantity: 250,
        status: "partial"
      )
    end

    action_candidate = ActionCandidate.create!(
      business:,
      title: "SEO改善候補",
      action_type: "seo_improvement",
      immediate_value_yen: 10_000,
      success_probability: 0.6,
      expected_hours: 2,
      execution_prompt: "梅田店舗を500件追加してください。"
    )

    assert_equal 0.52.to_d, action_candidate.success_probability
    assert_equal 2.4.to_d, action_candidate.expected_hours
    assert_equal 5_200, action_candidate.expected_profit_yen
    assert_equal "over_sized", action_candidate.metadata.dig("execution_feasibility_correction", "feasibility_label")
  end

  test "applies prediction calibration to expected profit without overwriting raw probability" do
    ActionPredictionCalibration.create!(
      action_type: "serp_research",
      sample_count: 10,
      profit_calibration_factor: 0.5,
      probability_calibration_factor: 0.8
    )

    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "SERP調査の補正テスト",
      action_type: "serp_research",
      immediate_value_yen: 10_000,
      success_probability: 0.5,
      expected_hours: 1
    )

    assert_equal 2_500, action_candidate.expected_profit_yen
    assert_equal 0.5.to_d, action_candidate.success_probability
    assert_equal 0.4.to_d, action_candidate.calibrated_success_probability
    assert_equal true, action_candidate.metadata.dig("prediction_calibration", "active")
    assert_equal "0.5", action_candidate.metadata.dig("prediction_calibration", "profit_calibration_factor")
  end
end
