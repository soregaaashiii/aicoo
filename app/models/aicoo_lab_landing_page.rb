class AicooLabLandingPage < ApplicationRecord
  STATUSES = %w[draft preview_ready approved rejected published unpublished].freeze
  PUBLIC_STATUSES = %w[draft scheduled published paused archived].freeze
  GENERATION_SOURCES = %w[manual candidate_conversion].freeze
  PAUSE_REASONS = %w[
    manual ai_quality policy copyright spam low_quality conversion_low runtime_error other
  ].freeze

  belongs_to :aicoo_lab_experiment
  has_many :aicoo_lab_landing_page_events, dependent: :destroy
  has_many :slug_histories,
           class_name: "AicooLabLandingPageSlugHistory",
           dependent: :destroy
  has_many :publication_events,
           class_name: "AicooLabLandingPagePublicationEvent",
           dependent: :destroy
  has_many :aicoo_lab_signups, dependent: :destroy

  before_validation :set_defaults
  before_update :record_published_slug_history, if: :will_save_change_to_published_slug?

  validates :status, inclusion: { in: STATUSES }
  validates :public_status, inclusion: { in: PUBLIC_STATUSES }
  validates :pause_reason, inclusion: { in: PAUSE_REASONS }, allow_blank: true
  validates :generation_source, inclusion: { in: GENERATION_SOURCES }
  validates :preview_slug, presence: true, uniqueness: true
  validates :assumed_price_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :with_public_slug, -> { where.not(published_slug: [ nil, "" ]) }
  scope :publicly_available, -> {
    with_public_slug.where(public_status: "published").where("published_at IS NULL OR published_at <= ?", Time.current)
  }
  scope :paused_public_pages, -> { with_public_slug.where(public_status: "paused") }
  scope :scheduled_for_publication, -> {
    where(public_status: "scheduled").where.not(scheduled_publish_at: nil).where(scheduled_publish_at: ..Time.current)
  }

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
      ensure_published_slug
      self.published_at = Time.current if published_at.blank?
      self.status = "published"
      self.public_status = "published"
      self.scheduled_publish_at = nil
      clear_pause_state
      save!
      record_publication_event!("publish", from_status: public_status_before_last_save, to_status: public_status)
      aicoo_lab_experiment.mark_status!("running")
    end
  end

  def unpublish!
    previous_status = public_status
    update!(status: "unpublished", public_status: "archived")
    record_publication_event!("archive", from_status: previous_status, to_status: "archived")
  end

  def schedule_publication!(scheduled_publish_at:)
    update!(
      public_status: "scheduled",
      scheduled_publish_at:,
      published_slug: published_slug.presence || unique_published_slug
    )
    record_publication_event!("schedule", from_status: public_status_before_last_save, to_status: "scheduled")
  end

  def publish_scheduled!
    transaction do
      ensure_published_slug
      self.published_at = scheduled_publish_at || Time.current
      self.public_status = "published"
      self.status = "published"
      self.scheduled_publish_at = nil
      clear_pause_state
      save!
      record_publication_event!("publish", from_status: public_status_before_last_save, to_status: public_status)
      aicoo_lab_experiment.mark_status!("running")
    end
  end

  def publicly_visible?
    public_status == "published" && published_slug.present? && (published_at.blank? || published_at <= Time.current)
  end

  def paused_publicly_visible?
    public_status == "paused" && published_slug.present?
  end

  def pause!(reason:, operator:, comment: nil, metadata: {})
    previous_status = public_status
    update!(
      public_status: "paused",
      pause_reason: reason.presence || "manual",
      pause_comment: comment,
      paused_at: Time.current,
      paused_by: operator.presence || "system"
    )
    record_publication_event!(
      "pause",
      from_status: previous_status,
      to_status: "paused",
      reason: pause_reason,
      operator: paused_by,
      comment: pause_comment,
      metadata:
    )
  end

  def resume!(operator:, comment: nil, metadata: {})
    previous_status = public_status
    update!(
      status: "published",
      public_status: "published",
      published_at: published_at.presence || Time.current,
      resumed_at: Time.current,
      resumed_by: operator.presence || "system",
      scheduled_publish_at: nil
    )
    record_publication_event!(
      "resume",
      from_status: previous_status,
      to_status: "published",
      reason: pause_reason,
      operator: resumed_by,
      comment:,
      metadata:
    )
    clear_pause_state
    save!
  end

  def ensure_published_slug
    self.published_slug = unique_published_slug if published_slug.blank?
    published_slug
  end

  def self.publish_due!
    scheduled_for_publication.find_each(&:publish_scheduled!)
  end

  def effective_seo_title
    seo_title.presence || headline
  end

  def effective_seo_description
    seo_description.presence || og_description.presence || subheadline.presence || body.to_s.truncate(155)
  end

  def effective_og_title
    og_title.presence || effective_seo_title
  end

  def effective_og_description
    og_description.presence || effective_seo_description
  end

  def effective_og_image_url
    og_image_url.presence
  end

  def paused?
    public_status == "paused"
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
    self.public_status = default_public_status if public_status.blank?
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

  def default_public_status
    case status
    when "published"
      "published"
    when "unpublished"
      "archived"
    else
      "draft"
    end
  end

  def unique_published_slug
    loop do
      slug = SecureRandom.urlsafe_base64(12).downcase
      next if AicooLabLandingPageSlugHistory.exists?(slug:)

      break slug unless self.class.exists?(published_slug: slug)
    end
  end

  def clear_pause_state
    self.pause_reason = nil
    self.pause_comment = nil
    self.paused_at = nil
    self.paused_by = nil
  end

  def record_publication_event!(event_type, from_status:, to_status:, reason: nil, operator: nil, comment: nil, metadata: {})
    publication_events.create!(
      event_type:,
      from_status:,
      to_status:,
      reason:,
      operator:,
      comment:,
      metadata:
    )
  end

  def record_published_slug_history
    previous_slug = published_slug_in_database
    return if previous_slug.blank? || previous_slug == published_slug

    slug_histories.find_or_create_by!(slug: previous_slug)
  end
end
