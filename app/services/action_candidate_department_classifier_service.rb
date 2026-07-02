class ActionCandidateDepartmentClassifierService
  Result = Data.define(:updated_count, :counts, :mode)

  REVENUE_ACTION_TYPES = %w[
    seo_article
    seo_improvement
    serp_research
    sales
    outsourcing
    automation
    feature_development
    ui_improvement
  ].freeze

  LAB_ACTION_TYPES = %w[data_preparation].freeze
  NEW_BUSINESS_ACTION_TYPES = %w[market_research new_business lp_experiment market_test build_lp build_mvp pivot].freeze

  REVENUE_KEYWORDS = %w[
    既存事業 改善 SEO seo CTR ctr CV cv 導線 店舗 店舗登録 記事 リライト GA4 ga4 GSC gsc SERP serp
    検索流入 売上 収益 CVR cvr 内部リンク
  ].freeze
  LAB_KEYWORDS = %w[
    実験 検証 LPテスト 仮説検証 学習データ proxy proxy_score 成長スコア ActionResult 日次指標
    採点 Judge 予測精度 データ整備 学習準備
  ].freeze
  NEW_BUSINESS_KEYWORDS = %w[
    新規事業 新サービス 立ち上げ MVP mvp 市場調査 新規LP 新規サービス 事業案
    市場 新規探索
  ].freeze

  def initialize(scope: ActionCandidate.all, overwrite: false)
    @scope = scope
    @overwrite = overwrite
  end

  def call
    updated_count = 0
    counts = ActionCandidate::DEPARTMENTS.index_with { 0 }

    candidates.find_each do |action_candidate|
      department = classify(action_candidate)
      counts[department] += 1
      next if action_candidate.department == department

      action_candidate.update!(department:)
      updated_count += 1
    end

    Result.new(updated_count:, counts:, mode: overwrite? ? "all" : "general_only")
  end

  def classify(action_candidate)
    text = classification_text(action_candidate)

    return "new_business" if keyword_match?(text, NEW_BUSINESS_KEYWORDS)
    return "lab" if keyword_match?(text, LAB_KEYWORDS)
    return "revenue" if keyword_match?(text, REVENUE_KEYWORDS)
    return "lab" if LAB_ACTION_TYPES.include?(action_candidate.action_type)
    return "new_business" if NEW_BUSINESS_ACTION_TYPES.include?(action_candidate.action_type)
    return "revenue" if REVENUE_ACTION_TYPES.include?(action_candidate.action_type)
    return "lab" if action_candidate.generation_source == "ai_reevaluation" && text.include?("学習")
    return "new_business" if action_candidate.generation_source == "ai_business" && text.include?("新規")

    "general"
  end

  private

  attr_reader :scope

  def candidates
    overwrite? ? scope : scope.where(department: "general")
  end

  def overwrite?
    @overwrite
  end

  def classification_text(action_candidate)
    [
      action_candidate.generation_source,
      action_candidate.action_type,
      action_candidate.business&.name,
      action_candidate.title,
      action_candidate.description,
      action_candidate.execution_prompt
    ].join(" ")
  end

  def keyword_match?(text, keywords)
    keywords.any? { |keyword| text.include?(keyword) }
  end
end
