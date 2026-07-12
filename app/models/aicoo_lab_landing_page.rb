class AicooLabLandingPage < ApplicationRecord
  include AicooActivityTrackable

  STATUSES = %w[draft preview_ready approved rejected published unpublished].freeze
  PUBLIC_STATUSES = %w[draft scheduled published paused archived].freeze
  GENERATION_SOURCES = %w[manual candidate_conversion].freeze
  PAUSE_REASONS = %w[
    manual ai_quality policy copyright spam low_quality conversion_low runtime_error other
  ].freeze
  PUBLIC_COPY_BANNED_TERMS = [
    "AICOO Lab",
    "AICOO",
    "LP実験",
    "低コストLP",
    "成果検証",
    "実験",
    "検証",
    "仮説",
    "Target user",
    "Problem",
    "Hypothesis",
    "Validation method",
    "Expected learning",
    "Rejection condition",
    "internal note",
    "admin note",
    "public_status",
    "公開中",
    "draft",
    "preview",
    "published",
    "archived"
  ].freeze

  belongs_to :aicoo_lab_experiment
  belongs_to :business, optional: true
  has_many :aicoo_lab_landing_page_events, dependent: :destroy
  has_many :slug_histories,
           class_name: "AicooLabLandingPageSlugHistory",
           dependent: :destroy
  has_many :publication_events,
           class_name: "AicooLabLandingPagePublicationEvent",
           dependent: :destroy
  has_many :aicoo_lab_signups, dependent: :destroy
  has_many :aicoo_pipeline_runs, dependent: :nullify

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
    with_public_slug.left_outer_joins(:business)
                    .where(public_status: "published")
                    .where("published_at IS NULL OR published_at <= ?", Time.current)
                    .where("businesses.id IS NULL OR businesses.deleted_at IS NULL")
  }
  scope :paused_public_pages, -> { with_public_slug.where(public_status: "paused") }
  scope :scheduled_for_publication, -> {
    left_outer_joins(:business)
      .where(public_status: "scheduled")
      .where.not(scheduled_publish_at: nil)
      .where(scheduled_publish_at: ..Time.current)
      .where("businesses.id IS NULL OR businesses.deleted_at IS NULL")
  }

  def self.build_from_experiment(experiment)
    new(
      aicoo_lab_experiment: experiment,
      headline: public_copy("#{experiment.market_category.presence || "市場"}向けの#{experiment.title}", fallback: experiment.title),
      subheadline: public_copy("面倒な作業を減らし、必要な準備をスムーズに進められるサービスです。"),
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

  def public_headline
    self.class.public_copy(headline, fallback: "サービスのご案内")
  end

  def public_subheadline
    self.class.public_copy(subheadline, fallback: "必要な準備をスムーズに進められるサービスです。")
  end

  def public_body
    self.class.public_copy(body, fallback: "詳しい内容を確認し、準備ができ次第ご案内します。")
  end

  def public_cta_text
    self.class.public_copy(cta_text, fallback: "事前登録する")
  end

  def public_seo_title
    self.class.public_copy(seo_title.presence || headline, fallback: public_headline)
  end

  def public_seo_description
    self.class.public_copy(
      seo_description.presence || og_description.presence || subheadline.presence || body.to_s.truncate(155),
      fallback: public_subheadline
    )
  end

  def public_og_title
    self.class.public_copy(og_title.presence || public_seo_title, fallback: public_headline)
  end

  def public_og_description
    self.class.public_copy(og_description.presence || public_seo_description, fallback: public_subheadline)
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

  def orphan_published?
    publicly_visible? && business.blank?
  end

  def ensure_business!(source: "published_landing_page_recovery")
    return business if business
    return Aicoo::IdeaPipeline::BusinessLinker.new(idea_pipeline_item).call if idea_pipeline_item

    recovered_business = recover_existing_business || create_business_from_landing_page!(source:)
    update!(business: recovered_business)
    candidate&.update!(business: recovered_business)
    recovered_business
  end

  def self.template_body(experiment)
    description = public_copy(
      experiment.description.presence || "お困りごとを整理し、必要な準備をスムーズに進められるサービスです。",
      fallback: "お困りごとを整理し、必要な準備をスムーズに進められるサービスです。"
    )
    notes = if internal_public_copy?(experiment.notes)
      nil
    else
      public_copy(experiment.notes, fallback: nil)
    end

    [
      description,
      notes,
      "まずは事前登録からお知らせを受け取れます。準備ができ次第、順番にご案内します。"
    ].compact_blank.join("\n\n")
  end

  def self.public_copy(value, fallback: "")
    text = value.to_s.dup
    return fallback if text.blank?

    PUBLIC_COPY_BANNED_TERMS.sort_by { |term| -term.length }.each do |term|
      text.gsub!(/#{Regexp.escape(term)}\s*[:：]?/i, "")
    end

    text.gsub!(/\b(?:draft|preview|published|archived)\b/i, "")
    text.gsub!(/(.{2,30}?向け)の\1/, '\1')
    text.gsub!("するです", "します")
    text.gsub!(/[ \t]+/, " ")
    text.gsub!(/[ \t]*\n[ \t]*/, "\n")
    text.gsub!(/\n{3,}/, "\n\n")
    text.gsub!(/\A[\s、。・:：-]+/, "")
    text.gsub!(/[\s、・:：-]+\z/, "")
    text.strip!

    text.presence || fallback
  end

  def self.internal_public_copy?(value)
    text = value.to_s
    return false if text.blank?

    PUBLIC_COPY_BANNED_TERMS.any? { |term| text.match?(/#{Regexp.escape(term)}/i) }
  end

  private

  def recover_existing_business
    candidate_business ||
      Business.real_businesses.find_by(name: public_headline) ||
      Business.real_businesses.find_by(name: aicoo_lab_experiment.title)
  end

  def candidate_business
    candidate&.business
  end

  def candidate
    @candidate ||= AicooLabExperimentCandidate.find_by(converted_experiment: aicoo_lab_experiment)
  end

  def idea_pipeline_item
    @idea_pipeline_item ||= IdeaPipelineItem.find_by(aicoo_lab_landing_page: self) ||
                            IdeaPipelineItem.find_by(aicoo_lab_experiment: aicoo_lab_experiment)
  end

  def create_business_from_landing_page!(source:)
    Business.create!(
      name: public_headline,
      description: public_subheadline.presence || public_body.truncate(240),
      category: aicoo_lab_experiment.market_category.presence || aicoo_lab_experiment.experiment_type,
      status: "launched",
      source:,
      idea_id: aicoo_lab_experiment.id,
      created_by_aicoo: true,
      launched: true,
      daily_run_enabled: true,
      serp_enabled: true,
      auto_revision_mode: "automatic",
      auto_deploy_mode: "approval",
      auto_build_enabled: true,
      auto_build_requires_approval: false,
      auto_build_risk_level: "low",
      new_lp_auto_deploy_enabled: true
    ).tap { |business| Aicoo::NewBusinessAutomationDefaults.apply!(business) }
  end

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
