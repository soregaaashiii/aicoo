class DataSourceCostProfile < ApplicationRecord
  EXECUTION_MODES = %w[auto smart manual].freeze
  SOURCE_DEFINITIONS = {
    "gsc" => { name: "Google Search Console", execution_mode: "auto", average_cost_yen: 0, average_expected_profit_yen: 0 },
    "ga4" => { name: "Google Analytics 4", execution_mode: "auto", average_cost_yen: 0, average_expected_profit_yen: 0 },
    "clarity" => { name: "Microsoft Clarity", execution_mode: "auto", average_cost_yen: 0, average_expected_profit_yen: 0 },
    "revenue" => { name: "Revenue", execution_mode: "auto", average_cost_yen: 0, average_expected_profit_yen: 0 },
    "business_metric_daily" => { name: "BusinessMetricDaily", execution_mode: "auto", average_cost_yen: 0, average_expected_profit_yen: 0 },
    "explore" => { name: "Explore", execution_mode: "smart", average_cost_yen: 5, average_expected_profit_yen: 500 },
    "opportunity_scan" => { name: "Opportunity Scan", execution_mode: "smart", average_cost_yen: 8, average_expected_profit_yen: 800 },
    "learning" => { name: "Learning", execution_mode: "smart", average_cost_yen: 0, average_expected_profit_yen: 0 },
    "serp" => { name: "SERP", execution_mode: "manual", average_cost_yen: 18, average_expected_profit_yen: 950 },
    "deep_research" => { name: "Deep Research", execution_mode: "manual", average_cost_yen: 150, average_expected_profit_yen: 5_000 },
    "openai" => { name: "OpenAI", execution_mode: "manual", average_cost_yen: 30, average_expected_profit_yen: 1_500 },
    "x" => { name: "X Search", execution_mode: "manual", average_cost_yen: 40, average_expected_profit_yen: 1_200 },
    "youtube" => { name: "YouTube Search", execution_mode: "manual", average_cost_yen: 25, average_expected_profit_yen: 900 },
    "google_ads" => { name: "Google Ads", execution_mode: "manual", average_cost_yen: 100, average_expected_profit_yen: 2_500 },
    "meta_ads" => { name: "Meta Ads", execution_mode: "manual", average_cost_yen: 100, average_expected_profit_yen: 2_000 }
  }.freeze

  has_many :business_data_source_settings, foreign_key: :source_key, primary_key: :source_key, inverse_of: :data_source_cost_profile

  validates :source_key, :name, presence: true
  validates :source_key, uniqueness: true
  validates :execution_mode, inclusion: { in: EXECUTION_MODES }
  validates :monthly_budget_yen, :monthly_spend_yen, :monthly_run_count, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :average_cost_yen, :average_expected_profit_yen, numericality: { greater_than_or_equal_to: 0 }

  before_validation :set_defaults

  scope :ordered, -> { order(Arel.sql("CASE execution_mode WHEN 'auto' THEN 1 WHEN 'smart' THEN 2 ELSE 3 END"), :source_key) }
  scope :enabled, -> { where(enabled: true) }

  def self.ensure_defaults!
    SOURCE_DEFINITIONS.each do |source_key, attributes|
      profile = find_or_initialize_by(source_key:)
      if profile.new_record?
        profile.assign_attributes(
          attributes.slice(:name, :execution_mode)
                    .merge(
                      average_cost_yen: attributes.fetch(:average_cost_yen),
                      average_expected_profit_yen: attributes.fetch(:average_expected_profit_yen)
                    )
        )
      end
      profile.save!
    end
  end

  def self.for_source(source_key)
    definition = SOURCE_DEFINITIONS[source_key] || {
      name: source_key.to_s.humanize,
      execution_mode: "manual",
      average_cost_yen: 0,
      average_expected_profit_yen: 0
    }
    find_by(source_key:) || definition.then do |definition|
      new(definition.merge(source_key:))
    end
  end

  def roi
    return nil if average_cost_yen.to_d.zero?

    average_expected_profit_yen.to_d / average_cost_yen.to_d
  end

  def monthly_budget_remaining_yen
    monthly_budget_yen.to_i - monthly_spend_yen.to_i
  end

  def cost_level
    return "free" if average_cost_yen.to_d.zero?
    return "high" if average_cost_yen.to_d >= 100

    execution_mode == "smart" ? "smart" : "paid"
  end

  def api_key_configured?
    api_key.present?
  end

  private

  def set_defaults
    definition = SOURCE_DEFINITIONS[source_key] || {}
    self.name = definition[:name] if name.blank?
    self.execution_mode = definition[:execution_mode] || "manual" if execution_mode.blank?
    self.enabled = true if enabled.nil?
    self.monthly_budget_yen = 0 if monthly_budget_yen.nil?
    self.monthly_spend_yen = 0 if monthly_spend_yen.nil?
    self.monthly_run_count = 0 if monthly_run_count.nil?
    self.average_cost_yen = definition[:average_cost_yen] || 0 if average_cost_yen.nil?
    if average_expected_profit_yen.nil?
      self.average_expected_profit_yen = definition[:average_expected_profit_yen] || 0
    end
    self.metadata = {} if metadata.blank?
  end
end
