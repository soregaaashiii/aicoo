class AicooLabLandingPage < ApplicationRecord
  STATUSES = %w[draft preview_ready approved rejected published unpublished].freeze
  GENERATION_SOURCES = %w[manual candidate_conversion].freeze

  belongs_to :aicoo_lab_experiment
  has_many :aicoo_lab_landing_page_events, dependent: :destroy
  has_many :aicoo_lab_signups, dependent: :destroy

  before_validation :set_defaults

  validates :status, inclusion: { in: STATUSES }
  validates :generation_source, inclusion: { in: GENERATION_SOURCES }
  validates :preview_slug, presence: true, uniqueness: true
  validates :assumed_price_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  def self.build_from_experiment(experiment)
    new(
      aicoo_lab_experiment: experiment,
      headline: "#{experiment.market_category.presence || "検証市場"}向けの#{experiment.title}",
      subheadline: "面倒な作業を減らし、低コストで成果検証できるサービスです。",
      body: template_body(experiment),
      cta_text: "事前登録する",
      assumed_price_yen: experiment.assumed_price_yen,
      generated_at: Time.current
    )
  end

  def mark_preview_ready!
    transaction do
      update!(status: "preview_ready")
      aicoo_lab_experiment.mark_status!("preview_ready")
    end
  end

  def publish!
    transaction do
      self.published_slug = unique_published_slug if published_slug.blank?
      self.published_at = Time.current if published_at.blank?
      self.status = "published"
      save!
      aicoo_lab_experiment.mark_status!("running")
    end
  end

  def unpublish!
    update!(status: "unpublished")
  end

  def publishable?
    status == "preview_ready" && aicoo_lab_experiment.approval_status == "approved"
  end

  def view_count
    event_count("view")
  end

  def cta_click_count
    event_count("cta_click")
  end

  def signup_count
    aicoo_lab_signups.count
  end

  def cta_rate
    rate(cta_click_count, view_count)
  end

  def signup_rate
    rate(signup_count, view_count)
  end

  def sample_threshold_reached?
    aicoo_lab_experiment.current_pv.to_i >= aicoo_lab_experiment.sample_pv_threshold.to_i
  end

  def self.template_body(experiment)
    description = experiment.description.presence || "この実験では、対象市場の課題に対して最小限のLPで需要を検証します。"
    notes = experiment.notes.presence || "LP公開後、PV・CTA反応・90日期待利益とのズレを記録して、AICOOの予測精度向上に使います。"

    <<~BODY.strip
      #{description}

      #{notes}

      まずは小さく公開し、十分なサンプルが集まった段階で結果を採点します。
    BODY
  end

  private

  def event_count(event_type)
    aicoo_lab_landing_page_events.where(event_type:).count
  end

  def rate(numerator, denominator)
    return nil if denominator.to_i.zero?

    numerator.to_d / denominator.to_d
  end

  def set_defaults
    self.status = "draft" if status.blank?
    self.generation_source = "manual" if generation_source.blank?
    self.cta_text = "事前登録する" if cta_text.blank?
    self.generated_at = Time.current if generated_at.blank?
    self.preview_slug = unique_preview_slug if preview_slug.blank?
  end

  def unique_preview_slug
    loop do
      slug = SecureRandom.urlsafe_base64(12).downcase
      break slug unless self.class.exists?(preview_slug: slug)
    end
  end

  def unique_published_slug
    loop do
      slug = SecureRandom.urlsafe_base64(12).downcase
      break slug unless self.class.exists?(published_slug: slug)
    end
  end
end
