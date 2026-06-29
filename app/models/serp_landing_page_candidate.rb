class SerpLandingPageCandidate < ApplicationRecord
  STATUSES = %w[proposed converted rejected].freeze

  belongs_to :serp_analysis, optional: true
  belongs_to :aicoo_lab_landing_page, optional: true

  before_validation :set_defaults

  validates :keyword, :lp_title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :expected_value_score, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :recent, -> { order(created_at: :desc) }
  scope :by_expected_value, -> { order(Arel.sql("expected_value_score DESC NULLS LAST, created_at DESC")) }

  def create_draft_landing_page!
    return aicoo_lab_landing_page if aicoo_lab_landing_page

    transaction do
      experiment = AicooLabExperiment.create!(experiment_attributes)
      landing_page = experiment.create_aicoo_lab_landing_page!(landing_page_attributes)
      update!(status: "converted", aicoo_lab_landing_page: landing_page)
      landing_page
    end
  end

  private

  def set_defaults
    self.status = "proposed" if status.blank?
    self.lp_title = service_name if lp_title.blank? && service_name.present?
    self.cta_text = "詳しく見る" if cta_text.blank?
    self.expected_value_score = 50 if expected_value_score.nil?
    self.metadata = {} if metadata.blank?
  end

  def experiment_attributes
    {
      title: lp_title,
      description: lp_description,
      experiment_type: "lp",
      market_category: keyword,
      acquisition_channel: "seo",
      status: "draft",
      approval_status: "not_required",
      expected_90d_profit_yen: expected_profit_yen,
      success_probability: success_probability,
      budget_yen: 0,
      estimated_work_minutes: 120,
      assumed_price_yen: 9_800,
      lp_word_count: 900,
      cta_count: 1,
      notes: experiment_notes
    }
  end

  def landing_page_attributes
    {
      headline: public_copy(lp_title),
      subheadline: public_copy(lp_description),
      body: landing_page_body,
      cta_text:,
      assumed_price_yen: 9_800,
      published_slug: suggested_slug,
      seo_title: public_copy(lp_title),
      seo_description: public_copy(lp_description),
      og_title: public_copy(lp_title),
      og_description: public_copy(lp_description),
      notes: competition_note,
      status: "draft",
      public_status: "draft",
      generation_source: "manual"
    }
  end

  def expected_profit_yen
    [ expected_value_score.to_i * 1_000, 10_000 ].max
  end

  def success_probability
    [ expected_value_score.to_d / 100, 0.8.to_d ].min
  end

  def experiment_notes
    [
      "SERP keyword: #{keyword}",
      "Target: #{target_audience}",
      "Problem: #{problem}",
      "Competition: #{competition_note}"
    ].compact_blank.join("\n\n")
  end

  def landing_page_body
    public_copy(<<~BODY.strip)
      #{problem}

      #{lp_description}

      必要な情報をまとめ、準備ができ次第ご案内します。
    BODY
  end

  def public_copy(value)
    AicooLabLandingPage.public_copy(value, fallback: "サービスのご案内")
  end

  def suggested_slug
    base = keyword.to_s.parameterize.presence || SecureRandom.urlsafe_base64(8).downcase
    candidate = base
    suffix = 2

    while AicooLabLandingPage.where(published_slug: candidate).exists? ||
          AicooLabLandingPageSlugHistory.where(slug: candidate).exists?
      candidate = "#{base}-#{suffix}"
      suffix += 1
    end

    candidate
  end
end
