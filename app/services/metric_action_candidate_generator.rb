class MetricActionCandidateGenerator
  Result = Data.define(:created, :skipped) do
    def created_count
      created.size
    end

    def skipped_count
      skipped.size
    end

    def diagnostics
      {
        "created_count" => created_count,
        "skipped_count" => skipped_count,
        "skipped_reasons" => skipped
      }
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
    Business.real_businesses.find_each.map { |business| new(business:).call }
  end

  def initialize(business:, today: Date.current)
    @business = business
    @today = today.to_date
  end

  def call
    return skipped_result("system/internal BusinessのためActionCandidate生成対象外です") if business.system_business?

    specs = candidate_specs
    return skipped_result(no_candidate_reason) if specs.empty?

    created = specs.filter_map { |spec| create_candidate(spec) }
    skipped = specs.size - created.size

    Result.new(created:, skipped: skipped_reasons + Array.new(skipped, "直近7日以内に類似候補があるため作成しませんでした"))
  end

  private

  attr_reader :business, :today

  def candidate_specs
    [
      setup_baseline_specs,
      early_stage_metric_specs,
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
    ].flatten.compact
  end

  def setup_baseline_specs
    [
      google_connection_spec,
      serp_optional_spec,
      lp_unpublished_spec,
      cta_setup_spec,
      article_activity_spec,
      shop_activity_spec
    ].compact
  end

  def early_stage_metric_specs
    return [] if metric_days_count >= 7

    [
      early_gsc_click_zero_spec,
      early_pv_zero_spec,
      early_conversion_path_spec,
      early_internal_link_spec
    ].compact
  end

  def google_connection_spec
    return if google_connected?

    CandidateSpec.new(
      key: "early_google_connection",
      title: "#{business.name}のGoogle計測を接続する",
      description: "GA4/GSCの紐付けが未完了のため、改善提案の精度が下がっています。",
      action_type: "data_preparation",
      immediate_value_yen: estimate_value(8_000),
      success_probability: 0.55,
      strategic_value_score: 50,
      risk_reduction_score: 70,
      expected_hours: 0.5,
      evaluation_reason: "Google連携不足: GA4/GSCの接続状態が確認できません。",
      execution_prompt: "#{business.name}のBusiness設定でGA4 PropertyとGSC Siteを紐付け、Google API取得が成功する状態にしてください。"
    )
  end

  def serp_optional_spec
    return unless business.respond_to?(:serp_enabled?) && business.serp_enabled?
    return unless Aicoo::Serp::OptionalMode.call.missing_key?

    CandidateSpec.new(
      key: "early_serp_optional_setup",
      title: "#{business.name}のSERP設定を確認する",
      description: "SERP API Keyが未設定のため、SEO競合分析とキーワード探索はスキップされています。",
      action_type: "data_preparation",
      immediate_value_yen: estimate_value(5_000),
      success_probability: 0.45,
      strategic_value_score: 35,
      risk_reduction_score: 35,
      expected_hours: 0.5,
      evaluation_reason: "SERP未設定: 任意データソースですが、設定すると提案精度が上がります。",
      execution_prompt: "#{business.name}でSERP分析を使うか判断し、必要ならSERP ProviderとAPI Key、対象キーワードを設定してください。"
    )
  end

  def lp_unpublished_spec
    return if published_landing_pages.exists?

    CandidateSpec.new(
      key: "early_lp_publish",
      title: "#{business.name}の公開LPを用意する",
      description: "公開LPがないため、流入・CTA・CVの検証が始められていません。",
      action_type: "build_lp",
      immediate_value_yen: estimate_value(12_000),
      success_probability: 0.35,
      strategic_value_score: 65,
      risk_reduction_score: 45,
      expected_hours: 1.5,
      evaluation_reason: "LP未公開: published状態の公開LPがありません。",
      execution_prompt: "#{business.name}の既存アイデアや説明から公開LPをdraft作成し、内容確認後にpublishedへ進めてください。"
    )
  end

  def cta_setup_spec
    return unless published_landing_pages.exists?
    return if published_landing_pages.any? { |landing_page| landing_page.public_cta_text.present? && landing_page.cta_click_count.positive? }

    CandidateSpec.new(
      key: "early_cta_setup",
      title: "#{business.name}のCTAを計測できる形にする",
      description: "公開LPはありますが、CTAクリックがまだ確認できません。",
      action_type: "ui_improvement",
      immediate_value_yen: estimate_value(10_000),
      success_probability: 0.34,
      strategic_value_score: 45,
      risk_reduction_score: 40,
      expected_hours: 1,
      evaluation_reason: "CTA未設定または未反応: 公開LPのCTAクリックが0です。",
      execution_prompt: "#{business.name}の公開LPで、ファーストビューと本文末のCTA文言・ボタン位置・計測イベントを確認し、クリックが記録される状態にしてください。"
    )
  end

  def article_activity_spec
    return if recent_article_activity_count.positive?
    return unless media_like_business?

    CandidateSpec.new(
      key: "early_article_content_shortage",
      title: "#{business.name}の記事・コンテンツを増やす",
      description: "記事作成/更新Activityが少なく、検索流入を増やす土台が不足しています。",
      action_type: "seo_article",
      immediate_value_yen: estimate_value(9_000),
      success_probability: 0.32,
      strategic_value_score: 50,
      risk_reduction_score: 25,
      expected_hours: 2,
      evaluation_reason: "記事数不足: 直近30日のArticle Activityがありません。",
      execution_prompt: "#{business.name}で狙うべき検索意図を1つ選び、LPまたは記事コンテンツを1本追加してください。公開後はActivity/ActionResultに記録してください。"
    )
  end

  def shop_activity_spec
    return if recent_shop_activity_count.positive?
    return unless shop_like_business?

    CandidateSpec.new(
      key: "early_shop_data_shortage",
      title: "#{business.name}の店舗データを増やす",
      description: "店舗追加/更新Activityが少なく、店舗DB型の改善余地があります。",
      action_type: "data_preparation",
      immediate_value_yen: estimate_value(8_000),
      success_probability: 0.4,
      strategic_value_score: 45,
      risk_reduction_score: 30,
      expected_hours: 1,
      evaluation_reason: "店舗数不足: 直近30日のShop Activityがありません。",
      execution_prompt: "#{business.name}で優先エリアを1つ決め、店舗データの追加・確認済み化・電話/地図導線の整備を行ってください。"
    )
  end

  def early_gsc_click_zero_spec
    return unless metric_days_count.positive?
    return if total_for_available_metrics(:clicks).positive?

    CandidateSpec.new(
      key: "early_gsc_click_zero",
      title: "#{business.name}の検索クリック0を改善する",
      description: "取得済みデータではGSCクリックがまだ0です。まず検索結果でクリックされる入口を作ります。",
      action_type: "seo_improvement",
      immediate_value_yen: estimate_value(7_000),
      success_probability: 0.28,
      strategic_value_score: 42,
      risk_reduction_score: 35,
      expected_hours: 1,
      evaluation_reason: "#{comparison_strategy_label}: clicksが0です。",
      execution_prompt: "#{business.name}のSEO title、meta description、公開LP/記事の冒頭を確認し、検索意図が伝わるタイトルと説明に更新してください。"
    )
  end

  def early_pv_zero_spec
    return unless metric_days_count.positive?
    return if total_for_available_metrics(:pageviews).positive? || total_for_available_metrics(:sessions).positive?

    CandidateSpec.new(
      key: "early_pv_zero",
      title: "#{business.name}のPV0を解消する",
      description: "取得済みデータではPV/sessionがまだ0です。公開導線または計測設定を確認します。",
      action_type: "data_preparation",
      immediate_value_yen: estimate_value(6_000),
      success_probability: 0.35,
      strategic_value_score: 38,
      risk_reduction_score: 55,
      expected_hours: 0.75,
      evaluation_reason: "#{comparison_strategy_label}: pageviews/sessionsが0です。",
      execution_prompt: "#{business.name}の公開URL、GA4計測タグ、内部リンク、公開LPへの導線を確認し、PVが記録される状態にしてください。"
    )
  end

  def early_conversion_path_spec
    return unless metric_days_count.positive?
    return unless total_for_available_metrics(:clicks).positive? || total_for_available_metrics(:pageviews).positive?
    return if total_for_available_metrics(:phone_clicks).positive? || total_for_available_metrics(:map_clicks).positive? || total_for_available_metrics(:affiliate_clicks).positive? || total_for_available_metrics(:conversions).positive?

    CandidateSpec.new(
      key: "early_conversion_path_missing",
      title: "#{business.name}の初期CV導線を追加する",
      description: "クリック/PVはありますが、電話・地図・アフィリエイト・CVがまだ確認できません。",
      action_type: "ui_improvement",
      immediate_value_yen: estimate_value(12_000),
      success_probability: 0.3,
      strategic_value_score: 48,
      risk_reduction_score: 35,
      expected_hours: 1,
      evaluation_reason: "#{comparison_strategy_label}: 反応はありますがCV系指標が0です。",
      execution_prompt: "#{business.name}の反応があるページに、問い合わせ・事前登録・電話・地図・予約・アフィリエイトなど収益に近いCTAを1つ追加してください。"
    )
  end

  def early_internal_link_spec
    return unless metric_days_count.positive?
    return unless total_for_available_metrics(:sessions).positive?
    return if average_views_per_session_for_available_metrics > 1.2

    CandidateSpec.new(
      key: "early_internal_link_shortage",
      title: "#{business.name}の初期内部リンクを整える",
      description: "sessionに対してpageviewsが少なく、次に見るページへの導線が不足している可能性があります。",
      action_type: "seo_improvement",
      immediate_value_yen: estimate_value(8_000),
      success_probability: 0.31,
      strategic_value_score: 40,
      risk_reduction_score: 25,
      expected_hours: 1,
      evaluation_reason: "#{comparison_strategy_label}: Views/Sessionが#{average_views_per_session_for_available_metrics.round(2)}です。",
      execution_prompt: "#{business.name}の流入ページから、関連LP・記事・店舗・CTAへの内部リンクを3件追加してください。"
    )
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
      metadata: candidate_metadata(spec),
      evaluation_reason: "metric_rule:#{spec.key}\n#{spec.evaluation_reason}",
      execution_prompt: spec.execution_prompt
    )
  end

  def candidate_metadata(spec)
    metadata = {
      "metric_rule" => spec.key,
      "comparison_strategy" => comparison_strategy,
      "metric_days_count" => metric_days_count,
      "low_confidence" => metric_days_count < 7,
      "confidence_note" => confidence_note
    }
    return metadata unless Aicoo::Serp::OptionalMode.call.missing_key?

    metadata.merge(
      "data_mode" => "internal_only",
      "missing_sources" => [ "serp" ],
      "confidence_penalty" => true
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
    when 0 then 15
    when 1..2 then 22
    when 3..6 then 30
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

  def available_metrics
    @available_metrics ||= recent30_metrics.sort_by(&:recorded_on)
  end

  def latest_metric
    available_metrics.last
  end

  def total_for_available_metrics(metric)
    available_metrics.sum { |record| record.public_send(metric).to_i }
  end

  def average_views_per_session_for_available_metrics
    sessions = total_for_available_metrics(:sessions)
    return 0.to_d if sessions.zero?

    total_for_available_metrics(:pageviews).to_d / sessions.to_d
  end

  def comparison_strategy
    case metric_days_count
    when 7.. then "seven_vs_thirty_days"
    when 3..6 then "recent_three_day_average"
    when 1..2 then "latest_vs_baseline"
    else "setup_baseline"
    end
  end

  def comparison_strategy_label
    case comparison_strategy
    when "seven_vs_thirty_days" then "7日 vs 30日比較"
    when "recent_three_day_average" then "直近3日平均"
    when "latest_vs_baseline" then "最新データとベースライン比較"
    else "初期設定ベースライン"
    end
  end

  def confidence_note
    return "7日以上のデータで比較しています。" if metric_days_count >= 7
    return "3〜6日のため直近3日平均を優先した低信頼度候補です。" if metric_days_count >= 3
    return "1〜2日のため最新データと初期ベースラインを使った低信頼度候補です。" if metric_days_count.positive?

    "BusinessMetricDailyがないため設定状態だけを使った低信頼度候補です。"
  end

  def google_connected?
    %w[gsc ga4].all? do |source_key|
      setting = business.business_data_source_settings.find { |item| item.source_key == source_key } ||
        BusinessDataSourceSetting.find_by(business:, source_key:)
      setting&.enabled? && setting&.linked?
    end
  end

  def published_landing_pages
    @published_landing_pages ||= business.aicoo_lab_landing_pages.publicly_available
  end

  def recent_article_activity_count
    @recent_article_activity_count ||= business.business_activity_logs
                                               .where(resource_type: "Article", occurred_at: 30.days.ago..Time.current)
                                               .count
  end

  def recent_shop_activity_count
    @recent_shop_activity_count ||= business.business_activity_logs
                                            .where(resource_type: "Shop", occurred_at: 30.days.ago..Time.current)
                                            .count
  end

  def media_like_business?
    text = "#{business.name} #{business.category} #{business.description}".downcase
    text.match?(/メディア|記事|seo|lp|コンテンツ|blog|media|article/) || published_landing_pages.exists?
  end

  def shop_like_business?
    text = "#{business.name} #{business.category} #{business.description}".downcase
    text.match?(/店舗|店|shop|restaurant|cafe|喫煙|吸えログ/)
  end

  def skipped_result(reason)
    Result.new(created: [], skipped: [ "#{business.name}: #{reason}" ])
  end

  def skipped_reasons
    @skipped_reasons ||= []
  end

  def no_candidate_reason
    [
      "改善候補生成条件に一致しません",
      "metric_days=#{metric_days_count}",
      "recent7_clicks=#{recent7_total(:clicks)}",
      "recent7_sessions=#{recent7_total(:sessions)}",
      "recent7_pageviews=#{recent7_total(:pageviews)}",
      "recent7_cv_clicks=#{recent7_cv_clicks}",
      "recent7_revenue=#{recent30_revenue.to_i}",
      "proxy_delta=#{proxy_delta.round(2)}",
      "条件: impressions増加+clicks停滞 / clicksあり+CVクリック0 / sessionsあり+回遊弱い / engagement低い / revenueあり / proxy変化あり のいずれにも未該当"
    ].join(" / ")
  end
end
