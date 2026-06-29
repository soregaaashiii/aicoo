class AicooLabExperimentCandidate < ApplicationRecord
  STATUSES = %w[proposed approved rejected converted].freeze
  GENERATION_SOURCES = %w[manual rule_based ai_paste].freeze
  TEMPLATES = {
    "low_cost_lp" => {
      name: "低コストLP実験",
      attributes: {
        title: "低コストLPで課題訴求を検証する",
        description: "LP公開以上の最小実験として、1つの課題と1つのCTAで需要を測る。",
        target_user: "課題を抱える小規模事業者",
        problem_statement: "課題の強さが不明なため、開発前に反応を確認したい。",
        hypothesis: "1つの課題訴求LPでも、一定のCTA反応があれば事業化余地がある。",
        validation_method: "LPを作成し、PV・CTAクリック・Signupを30日で測定する。",
        expected_learning: "訴求、価格、CTAの反応率から次に深掘りすべき市場か判断できる。",
        rejection_condition: "1000PV到達または90日経過時点でCTA率が1%未満なら棄却する。",
        experiment_type: "lp",
        acquisition_channel: "sns",
        expected_90d_profit_yen: 30_000,
        success_probability: 0.25,
        budget_yen: 1_000,
        estimated_work_minutes: 180,
        assumed_price_yen: 9_800,
        lp_word_count: 900,
        cta_count: 1,
        rationale: "低コストで早く公開でき、30日以内にPV/CTA反応を採点しやすい。"
      }
    },
    "seo" => {
      name: "SEO実験",
      attributes: {
        title: "ロングテールSEOページで検索需要を検証する",
        description: "低競合キーワードを1つ選び、検索意図に合わせたページを公開して90日で評価する。",
        target_user: "検索で具体的な解決策を探しているユーザー",
        problem_statement: "検索需要と競合強度のバランスが読めず、SEO投資判断が難しい。",
        hypothesis: "低競合ロングテールなら、少ない制作工数でも90日以内に検索流入が発生する。",
        validation_method: "SEOページを公開し、PV・CTAクリック・Signupを90日で測定する。",
        expected_learning: "キーワード選定、検索意図、CTAの組み合わせが有効か学習できる。",
        rejection_condition: "90日経過時点で検索流入またはCTA反応がほぼ無ければ棄却する。",
        experiment_type: "seo",
        acquisition_channel: "seo",
        expected_90d_profit_yen: 50_000,
        success_probability: 0.2,
        budget_yen: 0,
        estimated_work_minutes: 240,
        lp_word_count: 1_800,
        cta_count: 2,
        rationale: "採点速度は遅いが、無料継続でき、AICOOのSEO成功確率予測の教師データになる。"
      }
    },
    "saas" => {
      name: "SaaS検証",
      attributes: {
        title: "SaaSの手動運用MVPで支払い意思を検証する",
        description: "フル開発前に、手動運用と簡易フォームで課題・価格・継続意向を検証する。",
        target_user: "業務の一部を継続的に効率化したい小規模事業者",
        problem_statement: "本開発前に支払い意思と運用負荷を確認できていない。",
        hypothesis: "手動運用MVPでも課題が強ければ事前相談やSignupが発生する。",
        validation_method: "LPと簡易フォームで登録を集め、必要なら手動運用で価値提供する。",
        expected_learning: "価格、必要機能、初期運用負荷、継続意向を学習できる。",
        rejection_condition: "明確な支払い意思や継続利用意向が確認できなければ棄却する。",
        experiment_type: "saas",
        acquisition_channel: "direct",
        expected_90d_profit_yen: 120_000,
        success_probability: 0.15,
        budget_yen: 2_000,
        estimated_work_minutes: 480,
        assumed_price_yen: 19_800,
        development_minutes: 360,
        feature_count: 3,
        rationale: "開発前に課金仮説を採点でき、利益予測と工数予測のズレを学習できる。"
      }
    }
  }.freeze

  belongs_to :converted_experiment, class_name: "AicooLabExperiment", optional: true
  belongs_to :business, optional: true

  before_validation :set_defaults
  before_save :calculate_scores

  validates :title, presence: true
  validates :experiment_type, inclusion: { in: AicooLabExperiment::EXPERIMENT_TYPES }
  validates :acquisition_channel, inclusion: { in: AicooLabExperiment::ACQUISITION_CHANNELS }
  validates :status, inclusion: { in: STATUSES }
  validates :generation_source, inclusion: { in: GENERATION_SOURCES }
  validates :success_probability, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true
  validates :expected_90d_profit_yen, :budget_yen, :estimated_work_minutes, :assumed_price_yen, :lp_word_count,
            :cta_count, :development_minutes, :feature_count, :neglect_loss_90d_yen, :estimated_neglect_loss_90d_yen,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :by_lab_priority, -> { order(Arel.sql("lab_priority_score DESC NULLS LAST, expected_value_score DESC NULLS LAST")) }

  def self.from_template(template_key)
    template = TEMPLATES.fetch(template_key.presence || "low_cost_lp", TEMPLATES.fetch("low_cost_lp"))
    new(template.fetch(:attributes))
  end

  def approve!
    transaction do
      created_business = ensure_business!
      update!(status: "approved", business: created_business)
      created_business
    end
  end

  def reject!
    update!(status: "rejected")
  end

  def convert_to_experiment!
    transaction do
      created_business = ensure_business!
      experiment = AicooLabExperiment.create!(experiment_attributes)
      update!(status: "converted", converted_experiment: experiment, business: created_business)
      experiment
    end
  end

  def ensure_business!
    return business if business

    existing_business = Business.real_businesses.find_by(name: business_name)
    return existing_business if existing_business

    Business.create!(
      name: business_name,
      description: business_description,
      category: market_category.presence || experiment_type,
      status: "idea",
      source: "aicoo_lab_candidate",
      idea_id: id,
      created_by_aicoo: true,
      launched: false,
      daily_run_enabled: true,
      serp_enabled: true,
      auto_revision_mode: "manual"
    )
  end

  private

  def business_name
    name = title.to_s.strip.presence || "新規事業候補"
    return "#{name} 事業" if name.in?(Business::SYSTEM_BUSINESS_NAMES)

    name
  end

  def business_description
    [
      description,
      labeled_text("対象ユーザー", target_user),
      labeled_text("解決課題", problem_statement),
      labeled_text("仮説", hypothesis),
      labeled_text("検証方法", validation_method),
      labeled_text("収益モデル", assumed_price_yen.present? ? "想定単価 #{assumed_price_yen}円" : nil)
    ].compact_blank.join("\n\n")
  end

  def set_defaults
    self.experiment_type = "lp" if experiment_type.blank?
    self.acquisition_channel = "unknown" if acquisition_channel.blank?
    self.status = "proposed" if status.blank?
    self.generation_source = "manual" if generation_source.blank?
    self.expected_90d_profit_yen = 0 if expected_90d_profit_yen.blank?
    self.success_probability = 0 if success_probability.blank?
    self.budget_yen = 0 if budget_yen.blank?
    self.estimated_work_minutes = 0 if estimated_work_minutes.blank?
    self.neglect_loss_90d_yen = 0 if neglect_loss_90d_yen.blank?
    self.estimated_neglect_loss_90d_yen = 0 if estimated_neglect_loss_90d_yen.blank?
  end

  def calculate_scores
    setting = AicooLabSetting.current
    time_cost_yen = estimated_work_minutes.to_d / 60 * setting.hourly_cost_yen
    denominator = time_cost_yen + budget_yen.to_i

    self.expected_value_score = denominator.positive? ? expected_90d_profit_yen.to_d * success_probability.to_d / denominator : nil
    self.scoring_speed_score = 1.to_d / predicted_scoring_days
    self.lab_priority_score = expected_value_score ? expected_value_score * scoring_speed_score : nil
  end

  def predicted_scoring_days
    AicooLabExperiment::PREDICTED_SCORING_DAYS.fetch(experiment_type, 60)
  end

  def experiment_attributes
    {
      title:,
      description: experiment_description,
      experiment_type:,
      market_category:,
      acquisition_channel:,
      status: "draft",
      approval_status: "not_required",
      expected_90d_profit_yen:,
      success_probability:,
      budget_yen:,
      estimated_work_minutes:,
      assumed_price_yen:,
      lp_word_count:,
      cta_count:,
      development_minutes:,
      feature_count:,
      neglect_loss_90d_yen:,
      neglect_loss_reason:,
      estimated_neglect_loss_90d_yen:,
      neglect_loss_auto_generated:,
      notes: experiment_notes
    }
  end

  def experiment_description
    [
      description,
      labeled_text("Target user", target_user),
      labeled_text("Problem", problem_statement),
      labeled_text("Hypothesis", hypothesis),
      labeled_text("Validation method", validation_method)
    ].compact_blank.join("\n\n")
  end

  def experiment_notes
    [
      rationale,
      labeled_text("Expected learning", expected_learning),
      labeled_text("Rejection condition", rejection_condition)
    ].compact_blank.join("\n\n")
  end

  def labeled_text(label, value)
    return if value.blank?

    "#{label}: #{value}"
  end
end
