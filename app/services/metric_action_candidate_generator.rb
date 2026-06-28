class MetricActionCandidateGenerator
  Result = Data.define(:created, :skipped) do
    def created_count
      created.size
    end
  end

  CandidateSpec = Data.define(
    :key,
    :title,
    :description,
    :action_type,
    :immediate_value_yen,
    :success_probability,
    :strategic_value_score,
    :risk_reduction_score,
    :expected_hours,
    :evaluation_reason,
    :execution_prompt
  )

  METRICS = %i[
    impressions
    clicks
    sessions
    pageviews
    phone_clicks
    map_clicks
    affiliate_clicks
    users
    average_engagement_time_seconds
    conversions
    event_count
    scroll_events
    internal_search_events
  ].freeze

  def self.generate_all!
    Business.find_each.map { |business| new(business:).call }
  end

  def initialize(business:, today: Date.current)
    @business = business
    @today = today.to_date
  end

  def call
    return skipped_result("データ不足: BusinessMetricDaily が7日未満です") if metric_days_count < 7

    specs = candidate_specs
    created = specs.filter_map { |spec| create_candidate(spec) }
    skipped = specs.size - created.size

    Result.new(created:, skipped: skipped_reasons + Array.new(skipped, "直近7日以内に類似候補があるため作成しませんでした"))
  end

  private

  attr_reader :business, :today

  def candidate_specs
    [
      trend_spec,
      ctr_spec,
      conversion_spec,
      internal_link_spec,
      low_engagement_time_spec,
      low_navigation_spec,
      high_exit_path_spec,
      low_scroll_spec,
      revenue_spec,
      zero_revenue_spec
    ].compact
  end

  def trend_spec
    if proxy_delta.positive?
      CandidateSpec.new(
        key: "proxy_growth_reinforce",
        title: "#{business.name}の伸びている代理指標を強化する",
        description: "直近7日のproxy_scoreが30日平均より伸びているため、増加要因を特定して同種施策を増やします。",
        action_type: "seo_improvement",
        immediate_value_yen: estimate_value(30_000),
        success_probability: 0.45,
        strategic_value_score: 60,
        risk_reduction_score: 20,
        expected_hours: 2,
        evaluation_reason: "直近7日proxy_scoreが30日基準比で#{proxy_delta.round(2)}伸びています。",
        execution_prompt: "#{business.name}の直近7日で伸びた指標を確認し、流入・クリック・CV導線のうち伸びている要因を3つ抽出して、同じ型の改善案を実行してください。"
      )
    elsif proxy_delta.negative?
      CandidateSpec.new(
        key: "proxy_decline_repair",
        title: "#{business.name}の代理指標低下原因を調査して改善する",
        description: "直近7日のproxy_scoreが30日平均より落ちているため、原因調査と改善を行います。",
        action_type: "market_research",
        immediate_value_yen: estimate_value(20_000),
        success_probability: 0.35,
        strategic_value_score: 45,
        risk_reduction_score: 60,
        expected_hours: 2,
        evaluation_reason: "直近7日proxy_scoreが30日基準比で#{proxy_delta.round(2)}低下しています。",
        execution_prompt: "#{business.name}の直近7日と直近30日の代理指標を比較し、低下している指標、該当ページ・流入元、改善すべき導線を整理してください。"
      )
    end
  end

  def ctr_spec
    return unless metric_delta(:impressions).positive? && metric_delta(:clicks) <= 0

    CandidateSpec.new(
      key: "ctr_improvement",
      title: "#{business.name}のCTR改善を行う",
      description: "impressionsは伸びていますがclicksが伸びていないため、検索結果や導線のクリック率を改善します。",
      action_type: "seo_improvement",
      immediate_value_yen: estimate_value(25_000),
      success_probability: 0.4,
      strategic_value_score: 50,
      risk_reduction_score: 30,
      expected_hours: 1.5,
      evaluation_reason: "impressionsは増加、clicksは停滞しています。",
      execution_prompt: "#{business.name}で表示回数が増えているのにクリックが伸びていないページ・クエリを探し、title/meta description/導入文/CTAの改善案を作成してください。"
    )
  end

  def conversion_spec
    return unless recent7_total(:clicks).positive? && recent7_cv_clicks.zero?

    CandidateSpec.new(
      key: "conversion_path_improvement",
      title: "#{business.name}のCV導線を改善する",
      description: "clicksはある一方でphone/map/affiliate_clicksが少ないため、送客に近い導線を改善します。",
      action_type: "ui_improvement",
      immediate_value_yen: estimate_value(35_000),
      success_probability: 0.38,
      strategic_value_score: 55,
      risk_reduction_score: 35,
      expected_hours: 2,
      evaluation_reason: "直近7日にclicksがありますが、phone/map/affiliate_clicksが0です。",
      execution_prompt: "#{business.name}でクリックが発生しているページを確認し、電話・地図・アフィリエイトなど収益に近い導線を目立つ位置に追加または改善してください。"
    )
  end

  def internal_link_spec
    return unless recent7_total(:sessions).positive? && recent7_total(:pageviews) <= (recent7_total(:sessions) * 1.2)

    CandidateSpec.new(
      key: "internal_link_improvement",
      title: "#{business.name}の内部リンクと回遊導線を改善する",
      description: "sessions/pageviewsはあるものの回遊が弱いため、内部リンクや次アクション導線を改善します。",
      action_type: "seo_improvement",
      immediate_value_yen: estimate_value(18_000),
      success_probability: 0.36,
      strategic_value_score: 45,
      risk_reduction_score: 25,
      expected_hours: 1.5,
      evaluation_reason: "直近7日のpageviewsがsessionsの1.2倍以下で、回遊余地があります。",
      execution_prompt: "#{business.name}の流入ページから関連ページ・CV導線への内部リンクを追加し、ユーザーが次に見るべきページへ移動できる構造にしてください。"
    )
  end

  def low_engagement_time_spec
    return unless recent7_total(:sessions).positive?
    return unless recent7_average(:average_engagement_time_seconds) < 90

    CandidateSpec.new(
      key: "engagement_time_improvement",
      title: "#{business.name}の滞在時間が短いページを改善する",
      description: "GA4 Engagement上、平均滞在時間が短いため、冒頭・見出し・本文の読み進めやすさを改善します。",
      action_type: "seo_improvement",
      immediate_value_yen: estimate_value(22_000),
      success_probability: 0.37,
      strategic_value_score: 45,
      risk_reduction_score: 25,
      expected_hours: 1.5,
      evaluation_reason: "直近7日の平均滞在時間が#{recent7_average(:average_engagement_time_seconds).round}秒です。",
      execution_prompt: "#{business.name}で滞在時間が短い流入ページを確認し、冒頭文、見出し、本文の不足情報を改善してください。更新後は改善したページと変更内容をActionResultに記録してください。"
    )
  end

  def low_navigation_spec
    return unless recent7_total(:sessions).positive?
    return unless recent7_views_per_session <= 1.3

    CandidateSpec.new(
      key: "engagement_navigation_improvement",
      title: "#{business.name}の回遊率を上げる内部リンクを追加する",
      description: "GA4 Engagement上、Views/Sessionが低いため、関連記事・近隣ページ・次アクションへの導線を追加します。",
      action_type: "seo_improvement",
      immediate_value_yen: estimate_value(20_000),
      success_probability: 0.39,
      strategic_value_score: 48,
      risk_reduction_score: 22,
      expected_hours: 1.5,
      evaluation_reason: "直近7日のViews/Sessionが#{recent7_views_per_session.round(2)}です。",
      execution_prompt: "#{business.name}で流入があるが回遊が弱いページを確認し、関連ページ・近隣ページ・CV導線への内部リンクを3〜5件追加してください。"
    )
  end

  def high_exit_path_spec
    return unless recent7_total(:sessions).positive?
    return unless recent7_average_rate(:bounce_rate) >= 0.7 || recent7_conversion_rate <= 0.01

    CandidateSpec.new(
      key: "engagement_exit_path_improvement",
      title: "#{business.name}の離脱が多いページのCTAを改善する",
      description: "GA4 Engagement上、Bounce RateまたはCV率に課題があるため、電話・地図・予約などの次アクション導線を改善します。",
      action_type: "ui_improvement",
      immediate_value_yen: estimate_value(28_000),
      success_probability: 0.36,
      strategic_value_score: 52,
      risk_reduction_score: 32,
      expected_hours: 2,
      evaluation_reason: "直近7日のBounce Rateは#{(recent7_average_rate(:bounce_rate) * 100).round(1)}%、CV率は#{(recent7_conversion_rate * 100).round(1)}%です。",
      execution_prompt: "#{business.name}で離脱が多いページを確認し、電話・地図・予約・問い合わせなど収益に近いCTAをファーストビューと本文末に追加または改善してください。"
    )
  end

  def low_scroll_spec
    return unless recent7_total(:sessions).positive?
    return unless recent7_total(:scroll_events).positive?
    return unless recent7_scroll_rate < 0.35

    CandidateSpec.new(
      key: "engagement_scroll_improvement",
      title: "#{business.name}のスクロール率が低いページの冒頭を改善する",
      description: "GA4 Engagement上、Scroll Eventが少ないため、冒頭で読む理由と次の見出しまでの導線を改善します。",
      action_type: "seo_improvement",
      immediate_value_yen: estimate_value(16_000),
      success_probability: 0.35,
      strategic_value_score: 42,
      risk_reduction_score: 25,
      expected_hours: 1,
      evaluation_reason: "直近7日のScroll率が#{(recent7_scroll_rate * 100).round(1)}%です。",
      execution_prompt: "#{business.name}でスクロール率が低いページを確認し、冒頭文、目次、最初の見出し、CTA前の説明を改善して読み進めやすくしてください。"
    )
  end

  def revenue_spec
    return unless recent30_revenue.positive?

    CandidateSpec.new(
      key: "revenue_expansion",
      title: "#{business.name}の収益発生施策を横展開する",
      description: "収益が発生しているため、利益につながった導線や施策を拡大します。",
      action_type: "sales",
      immediate_value_yen: [ recent30_revenue * 2, 10_000 ].max,
      success_probability: 0.5,
      strategic_value_score: 55,
      risk_reduction_score: 20,
      expected_hours: 2,
      evaluation_reason: "直近30日に#{recent30_revenue}円の売上があります。",
      execution_prompt: "#{business.name}で直近30日の売上が発生したページ・導線・商品を特定し、同じ勝ち筋を別ページや別チャネルへ横展開してください。"
    )
  end

  def zero_revenue_spec
    return if cumulative_revenue.positive?

    if proxy_delta.positive?
      CandidateSpec.new(
        key: "zero_revenue_continue_validation",
        title: "#{business.name}の検証を継続して収益導線を追加する",
        description: "収益はまだありませんがproxy_scoreは伸びているため、検証を継続しつつ収益導線を足します。",
        action_type: "build_lp",
        immediate_value_yen: estimate_value(15_000),
        success_probability: 0.3,
        strategic_value_score: 60,
        risk_reduction_score: 35,
        expected_hours: 2,
        evaluation_reason: "収益0円ですがproxy_scoreが伸びています。",
        execution_prompt: "#{business.name}で伸びている代理指標を維持しながら、問い合わせ・事前登録・アフィリエイトなど収益に近い導線を1つ追加してください。"
      )
    elsif proxy_delta.negative?
      CandidateSpec.new(
        key: "zero_revenue_pause_or_withdraw",
        title: "#{business.name}の保留または撤退判断を行う",
        description: "収益がなくproxy_scoreも低下しているため、追加投資前に保留・撤退基準を確認します。",
        action_type: "withdraw",
        immediate_value_yen: 0,
        success_probability: 0.4,
        strategic_value_score: 20,
        risk_reduction_score: 80,
        expected_hours: 1,
        evaluation_reason: "収益0円かつproxy_scoreが低下しています。",
        execution_prompt: "#{business.name}について、直近30日の代理指標、投入工数、今後の収益化可能性を確認し、継続・保留・撤退の判断基準を整理してください。"
      )
    end
  end

  def create_candidate(spec)
    if recent_duplicate?(spec)
      skipped_reasons << "#{spec.key}: duplicate"
      return
    end

    business.action_candidates.create!(
      title: spec.title,
      description: spec.description,
      action_type: spec.action_type,
      immediate_value_yen: spec.immediate_value_yen,
      success_probability: spec.success_probability,
      strategic_value_score: spec.strategic_value_score,
      risk_reduction_score: spec.risk_reduction_score,
      confidence_score: confidence_score,
      data_confidence_score: confidence_score,
      expected_hours: spec.expected_hours,
      cost_yen: 0,
      status: "idea",
      generation_source: "ai_business",
      metadata: { "metric_rule" => spec.key },
      evaluation_reason: "metric_rule:#{spec.key}\n#{spec.evaluation_reason}",
      execution_prompt: spec.execution_prompt
    )
  end

  def recent_duplicate?(spec)
    business.action_candidates
            .where(created_at: duplicate_window_start..)
            .where("title = ? OR evaluation_reason LIKE ?", spec.title, "%metric_rule:#{spec.key}%")
            .exists?
  end

  def duplicate_window_start
    today.beginning_of_day - 7.days
  end

  def proxy_delta
    @proxy_delta ||= recent7_proxy_score - normalized_30d_proxy_score
  end

  def metric_delta(metric)
    recent7_total(metric) - normalized_30d_total(metric)
  end

  def recent7_proxy_score
    recent7_metrics.sum(&:proxy_score)
  end

  def normalized_30d_proxy_score
    recent30_metrics.sum(&:proxy_score).to_d / [ recent30_metrics.size, 1 ].max * 7
  end

  def recent7_total(metric)
    recent7_metrics.sum { |record| record.public_send(metric).to_i }
  end

  def normalized_30d_total(metric)
    recent30_metrics.sum { |record| record.public_send(metric).to_i }.to_d / [ recent30_metrics.size, 1 ].max * 7
  end

  def recent7_average(metric)
    values = recent7_metrics.filter_map { |record| record.public_send(metric).to_d if record.public_send(metric).to_d.positive? }
    return 0.to_d if values.empty?

    values.sum / values.size
  end

  def recent7_average_rate(metric)
    recent7_average(metric)
  end

  def recent7_views_per_session
    return 0.to_d if recent7_total(:sessions).zero?

    recent7_total(:pageviews).to_d / recent7_total(:sessions).to_d
  end

  def recent7_conversion_rate
    return 0.to_d if recent7_total(:sessions).zero?

    recent7_total(:conversions).to_d / recent7_total(:sessions).to_d
  end

  def recent7_scroll_rate
    return 0.to_d if recent7_total(:sessions).zero?

    recent7_total(:scroll_events).to_d / recent7_total(:sessions).to_d
  end

  def recent7_cv_clicks
    recent7_total(:phone_clicks) + recent7_total(:map_clicks) + recent7_total(:affiliate_clicks)
  end

  def recent30_revenue
    business.revenue_events.revenue.where(occurred_on: recent30_range).sum(:amount)
  end

  def cumulative_revenue
    business.revenue_events.revenue.sum(:amount)
  end

  def metric_days_count
    recent30_metrics.size
  end

  def confidence_score
    case metric_days_count
    when 0...7 then 0
    when 7...14 then 30
    when 14...30 then 45
    else 60
    end
  end

  def estimate_value(base_value)
    [ base_value + recent30_revenue, base_value * 3 ].min
  end

  def recent7_metrics
    @recent7_metrics ||= business.business_metric_dailies.where(recorded_on: recent7_range).to_a
  end

  def recent30_metrics
    @recent30_metrics ||= business.business_metric_dailies.where(recorded_on: recent30_range).to_a
  end

  def recent7_range
    (today - 6)..today
  end

  def recent30_range
    (today - 29)..today
  end

  def skipped_result(reason)
    Result.new(created: [], skipped: [ reason ])
  end

  def skipped_reasons
    @skipped_reasons ||= []
  end
end
