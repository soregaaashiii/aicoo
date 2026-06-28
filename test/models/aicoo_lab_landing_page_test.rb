require "test_helper"

class AicooLabLandingPageTest < ActiveSupport::TestCase
  test "generates preview slug and template content" do
    experiment = AicooLabExperiment.create!(
      title: "予約管理の需要検証",
      description: "予約管理を楽にするLP実験です。",
      experiment_type: "lp",
      market_category: "美容室",
      acquisition_channel: "sns",
      assumed_price_yen: 9_800,
      notes: "予約漏れを減らせるかを確認します。"
    )

    landing_page = AicooLabLandingPage.build_from_experiment(experiment)
    landing_page.save!

    assert_equal "美容室向けの予約管理の需要検証", landing_page.headline
    assert_equal "事前登録する", landing_page.cta_text
    assert_equal 9_800, landing_page.assumed_price_yen
    assert landing_page.preview_slug.present?
    assert_includes landing_page.body, "予約管理を楽にするLP実験です。"
  end

  test "marks landing page and experiment preview ready" do
    experiment = AicooLabExperiment.create!(title: "Preview test", experiment_type: "lp", acquisition_channel: "sns")
    landing_page = experiment.create_aicoo_lab_landing_page!(
      headline: "Preview headline",
      subheadline: "Preview subheadline",
      body: "Preview body",
      cta_text: "事前登録する"
    )

    landing_page.mark_preview_ready!

    assert_equal "preview_ready", landing_page.status
    assert_equal "preview_ready", experiment.reload.status
  end

  test "publishes scheduled landing pages when due" do
    experiment = AicooLabExperiment.create!(title: "Scheduled test", experiment_type: "lp", acquisition_channel: "sns")
    landing_page = experiment.create_aicoo_lab_landing_page!(
      headline: "Scheduled headline",
      subheadline: "Scheduled subheadline",
      body: "Scheduled body",
      cta_text: "事前登録する",
      public_status: "scheduled",
      scheduled_publish_at: 1.minute.ago,
      published_slug: "scheduled-model-lp"
    )

    AicooLabLandingPage.publish_due!

    landing_page.reload
    assert_equal "published", landing_page.public_status
    assert_equal "published", landing_page.status
    assert_nil landing_page.scheduled_publish_at
    assert landing_page.publicly_visible?
  end

  test "records published slug history when slug changes" do
    experiment = AicooLabExperiment.create!(title: "Slug history test", experiment_type: "lp", acquisition_channel: "sns")
    landing_page = experiment.create_aicoo_lab_landing_page!(
      headline: "Slug headline",
      subheadline: "Slug subheadline",
      body: "Slug body",
      cta_text: "事前登録する",
      status: "published",
      public_status: "published",
      published_at: Time.current,
      published_slug: "first-slug"
    )

    assert_difference("AicooLabLandingPageSlugHistory.count", 1) do
      landing_page.update!(published_slug: "second-slug")
    end

    assert_equal "first-slug", landing_page.slug_histories.last.slug
  end
end
