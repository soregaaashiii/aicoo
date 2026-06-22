class ActionCandidateDepartmentRanking
  DEPARTMENTS = {
    "general" => "総合",
    "revenue" => "Revenue",
    "lab" => "Lab",
    "new_business" => "新規事業"
  }.freeze

  Result = Data.define(:active_department, :tabs, :rankings, :department_leaders)
  Tab = Data.define(:key, :label, :path)
  Row = Data.define(:score, :department_score, :badges) do
    def action_candidate
      score.action_candidate
    end

    def judge_adjusted_score
      score.judge_adjusted_score
    end

    def summary_reason
      case department_score.department
      when "revenue"
        revenue_reason
      when "lab"
        lab_reason
      when "new_business"
        new_business_reason
      else
        "Judge補正後 #{format_decimal(judge_adjusted_score)}"
      end
    end

    private

    def revenue_reason
      [
        "期待利益 #{format_yen(department_score.expected_profit_yen)}",
        "期待時給 #{department_score.expected_hourly_value_yen ? format_yen(department_score.expected_hourly_value_yen) : '-'}",
        first_badge
      ].compact.join(" / ")
    end

    def lab_reason
      [
        "学習価値 #{format_yen(department_score.learning_value_yen)}",
        department_score.experiment_cost_yen.to_i <= 500 ? "低コスト" : "コスト #{format_yen(department_score.experiment_cost_yen)}",
        first_badge
      ].compact.join(" / ")
    end

    def new_business_reason
      [
        "市場規模 #{format_decimal(department_score.market_size_score)}",
        "自動化率 #{format_decimal(department_score.automation_rate_score)}",
        first_badge
      ].compact.join(" / ")
    end

    def first_badge
      badges.first
    end

    def format_yen(value)
      "¥#{value.to_i.to_fs(:delimited)}"
    end

    def format_decimal(value)
      return "-" if value.nil?

      value.to_d.round(1).to_s
    end
  end
  DepartmentScore = Data.define(
    :department,
    :value,
    :expected_profit_yen,
    :expected_hourly_value_yen,
    :success_probability,
    :roi,
    :learning_value_yen,
    :data_confidence_score,
    :experiment_cost_yen,
    :execution_hours,
    :market_size_score,
    :automation_rate_score,
    :launch_speed_score
  )

  def initialize(active_department: "general", limit: 10)
    @active_department = active_department.presence_in(DEPARTMENTS.keys) || "general"
    @limit = limit
    @score_builder = AicooJudge::ActionCandidateScore.new
  end

  def call
    Result.new(
      active_department:,
      tabs: tabs,
      rankings: ranking_for(active_department),
      department_leaders: department_leaders
    )
  end

  def ranking_for(department, limit: @limit)
    ranked_scores(scope_for(department), department:).first(limit)
  end

  private

  attr_reader :active_department, :limit, :score_builder

  def tabs
    DEPARTMENTS.map do |key, label|
      Tab.new(key:, label:, path: Rails.application.routes.url_helpers.department_rankings_path(department: key))
    end
  end

  def department_leaders
    DEPARTMENTS.except("general").keys.index_with do |department|
      ranking_for(department, limit: 1).first
    end
  end

  def ranked_scores(scope, department:)
    rows = scope.includes(:business)
                .to_a
                .map { |action_candidate| build_row(action_candidate) }
    rows.sort_by { |row| sort_key(row, department:) }
  end

  def scope_for(department)
    scope = ActionCandidate.active_for_ranking
    return scope.where.not(action_type: "data_preparation") if department == "general"

    scope.where(department:)
  end

  def build_row(action_candidate)
    Row.new(
      score: score_builder.score_for(action_candidate),
      department_score: department_score_for(action_candidate),
      badges: badges_for(action_candidate)
    )
  end

  def sort_key(row, department:)
    if department == "general"
      [ -row.judge_adjusted_score.to_d, -row.action_candidate.expected_profit_yen.to_i, row.action_candidate.title.to_s ]
    else
      [ -row.department_score.value.to_d, -row.judge_adjusted_score.to_d, row.action_candidate.title.to_s ]
    end
  end

  def department_score_for(action_candidate)
    case action_candidate.department
    when "revenue"
      revenue_score(action_candidate)
    when "lab"
      lab_score(action_candidate)
    when "new_business"
      new_business_score(action_candidate)
    else
      general_score(action_candidate)
    end
  end

  def revenue_score(action_candidate)
    hourly = action_candidate.expected_hourly_value_yen.to_i
    roi = action_candidate.roi.to_d
    value = action_candidate.expected_profit_yen.to_i +
            (hourly * 0.5) +
            (roi.positive? ? [ roi * 1_000, 20_000 ].min : 0) +
            (action_candidate.success_probability.to_d * 10_000)
    score("revenue", value, action_candidate)
  end

  def lab_score(action_candidate)
    learning_value = action_candidate.expected_learning_value_yen.to_i
    confidence_gain = action_candidate.data_confidence_score.to_i * 100
    experiment_speed = speed_score(action_candidate.expected_hours) * 100
    cost_efficiency = [ 10_000 - action_candidate.cost_yen.to_i, 0 ].max
    value = learning_value + confidence_gain + experiment_speed + cost_efficiency
    score("lab", value, action_candidate)
  end

  def new_business_score(action_candidate)
    market_size = metadata_number(action_candidate, "market_size_score", fallback: action_candidate.strategic_value_score.to_i)
    automation_rate = metadata_number(action_candidate, "automation_rate_score", fallback: automation_rate_fallback(action_candidate))
    launch_speed = metadata_number(action_candidate, "launch_speed_score", fallback: speed_score(action_candidate.expected_hours))
    value = (market_size * 150) + (automation_rate * 100) + (launch_speed * 100) + (action_candidate.success_probability.to_d * 10_000)
    score("new_business", value, action_candidate, market_size:, automation_rate:, launch_speed:)
  end

  def general_score(action_candidate)
    score("general", score_builder.score_for(action_candidate).judge_adjusted_score.to_d, action_candidate)
  end

  def score(department, value, action_candidate, market_size: nil, automation_rate: nil, launch_speed: nil)
    DepartmentScore.new(
      department:,
      value: value.to_d,
      expected_profit_yen: action_candidate.expected_profit_yen.to_i,
      expected_hourly_value_yen: action_candidate.expected_hourly_value_yen,
      success_probability: action_candidate.success_probability,
      roi: action_candidate.roi,
      learning_value_yen: action_candidate.expected_learning_value_yen.to_i,
      data_confidence_score: action_candidate.data_confidence_score.to_i,
      experiment_cost_yen: action_candidate.cost_yen.to_i,
      execution_hours: action_candidate.expected_hours,
      market_size_score: market_size,
      automation_rate_score: automation_rate,
      launch_speed_score: launch_speed
    )
  end

  def metadata_number(action_candidate, key, fallback:)
    value = action_candidate.metadata.to_h[key]
    return fallback.to_d if value.blank?

    value.to_d
  end

  def automation_rate_fallback(action_candidate)
    return 80 if action_candidate.action_type == "automation"
    return 70 if action_candidate.execution_prompt.to_s.include?("自動")

    action_candidate.data_confidence_score.to_i
  end

  def speed_score(hours)
    return 100 if hours.blank? || hours.to_d.zero?

    (100 / [ hours.to_d, 1 ].max).clamp(10, 100)
  end

  def badges_for(action_candidate)
    text = [
      action_candidate.title,
      action_candidate.description,
      action_candidate.execution_prompt,
      action_candidate.evaluation_reason,
      action_candidate.action_type
    ].join(" ")
    badge_rules.filter_map do |label, keywords|
      label if keywords.any? { |keyword| text.include?(keyword) }
    end
  end

  def badge_rules
    {
      "CTR改善" => %w[CTR ctr],
      "CV改善" => %w[CV cv CVR cvr コンバージョン 導線],
      "売上改善" => %w[売上 収益 revenue],
      "GSC/GA4/SERP由来" => %w[GSC gsc GA4 ga4 SERP serp],
      "仮説検証" => %w[仮説 検証],
      "LP実験" => %w[LP lp LPテスト],
      "学習データ収集" => %w[学習データ ActionResult 採点],
      "proxy score改善" => %w[proxy proxy_score 成長スコア],
      "MVP" => %w[MVP mvp],
      "市場調査" => %w[市場調査 市場],
      "新規LP" => %w[新規LP 新規 lp],
      "新サービス立ち上げ" => %w[新サービス 立ち上げ]
    }
  end
end
