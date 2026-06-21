class AicooLabCandidateGenerator
  Result = Data.define(:created_candidates, :generation_run)

  ACTIVE_STATUSES = %w[proposed approved converted].freeze
  GENERATION_SOURCE = "rule_based"

  CANDIDATE_SPECS = [
    {
      title: "小規模美容室向け予約前FAQ LP実験",
      description: "予約前によくある不安を1ページで解消し、事前相談CTAへの反応を測る。",
      experiment_type: "lp",
      market_category: "小規模美容室",
      acquisition_channel: "seo",
      expected_90d_profit_yen: 45_000,
      success_probability: 0.28,
      budget_yen: 0,
      estimated_work_minutes: 75,
      assumed_price_yen: 9_800,
      lp_word_count: 900,
      cta_count: 1,
      rationale: "低コストで公開でき、悩みの明確な店舗系市場のCV反応を30日で見られる。"
    },
    {
      title: "士業向け問い合わせ整理AIツールLP実験",
      description: "問い合わせ内容を自動分類するAI補助ツールの需要をLPと事前登録で測る。",
      experiment_type: "ai_tool",
      market_category: "士業",
      acquisition_channel: "direct",
      expected_90d_profit_yen: 80_000,
      success_probability: 0.2,
      budget_yen: 300,
      estimated_work_minutes: 100,
      assumed_price_yen: 14_800,
      lp_word_count: 1_000,
      cta_count: 1,
      development_minutes: 60,
      feature_count: 2,
      rationale: "手作業の困り度が高く、AI化の価値をLPだけで先に検証できる。"
    },
    {
      title: "喫煙可能カフェの駅名ロングテールSEO実験",
      description: "駅名と喫煙可能カフェを掛け合わせた低競合ページを作り、検索流入を測る。",
      experiment_type: "seo",
      market_category: "ローカル検索",
      acquisition_channel: "seo",
      expected_90d_profit_yen: 35_000,
      success_probability: 0.24,
      budget_yen: 0,
      estimated_work_minutes: 90,
      lp_word_count: 1_500,
      cta_count: 2,
      rationale: "既存SEO知見と相性が良く、追加費用なしで検索需要と競合強度を採点できる。"
    },
    {
      title: "夜職向け勤怠メモSaaS手動MVP検証",
      description: "シフト変更と勤怠メモをフォームで受け、手動運用で課金意向を確認する。",
      experiment_type: "saas",
      market_category: "夜職店舗",
      acquisition_channel: "direct",
      expected_90d_profit_yen: 120_000,
      success_probability: 0.16,
      budget_yen: 500,
      estimated_work_minutes: 120,
      assumed_price_yen: 19_800,
      lp_word_count: 800,
      cta_count: 1,
      development_minutes: 90,
      feature_count: 3,
      rationale: "本開発前に手動運用で価格と運用負荷を測れるため、資本効率が高い。"
    },
    {
      title: "フリーランス向け請求前チェックリストLP実験",
      description: "請求漏れを防ぐチェックリスト配布LPでメール登録率を測る。",
      experiment_type: "lp",
      market_category: "フリーランス",
      acquisition_channel: "sns",
      expected_90d_profit_yen: 30_000,
      success_probability: 0.32,
      budget_yen: 0,
      estimated_work_minutes: 45,
      assumed_price_yen: 4_980,
      lp_word_count: 700,
      cta_count: 1,
      rationale: "作成工数が小さく、登録率から課題の強さをすぐに判断できる。"
    },
    {
      title: "地域別レンタルスペース比較ディレクトリ検証",
      description: "地域と用途を絞った比較ディレクトリの1カテゴリだけを作り、CTA反応を測る。",
      experiment_type: "directory_site",
      market_category: "レンタルスペース",
      acquisition_channel: "seo",
      expected_90d_profit_yen: 55_000,
      success_probability: 0.18,
      budget_yen: 0,
      estimated_work_minutes: 110,
      lp_word_count: 1_600,
      cta_count: 2,
      rationale: "ディレクトリ型の検索需要を小さく試せ、将来の横展開余地も評価できる。"
    },
    {
      title: "飲食店向けGoogle口コミ返信AI LP実験",
      description: "口コミ返信文をAIで作る訴求に絞り、事前登録と相談CTAを測る。",
      experiment_type: "ai_tool",
      market_category: "飲食店",
      acquisition_channel: "seo",
      expected_90d_profit_yen: 75_000,
      success_probability: 0.22,
      budget_yen: 300,
      estimated_work_minutes: 90,
      assumed_price_yen: 9_800,
      lp_word_count: 900,
      cta_count: 1,
      development_minutes: 60,
      feature_count: 2,
      rationale: "運営コストを下げる明確なAI用途で、低予算でも需要検証しやすい。"
    },
    {
      title: "不動産内見チェックLP実験",
      description: "内見時の見落としを防ぐチェック項目を訴求し、PDF配布CTAの反応を測る。",
      experiment_type: "lp",
      market_category: "賃貸検討者",
      acquisition_channel: "sns",
      expected_90d_profit_yen: 28_000,
      success_probability: 0.3,
      budget_yen: 0,
      estimated_work_minutes: 50,
      assumed_price_yen: 2_980,
      lp_word_count: 700,
      cta_count: 1,
      rationale: "悩みが具体的でLP作成が軽く、CTA率の教師データを低コストで増やせる。"
    },
    {
      title: "中古スマホ購入前診断SEO実験",
      description: "中古スマホ購入前の確認項目に絞ったSEOページで検索反応を測る。",
      experiment_type: "seo",
      market_category: "中古スマホ",
      acquisition_channel: "seo",
      expected_90d_profit_yen: 42_000,
      success_probability: 0.21,
      budget_yen: 0,
      estimated_work_minutes: 100,
      lp_word_count: 1_700,
      cta_count: 2,
      rationale: "購買直前の検索意図が強く、成果までの距離が近いSEO教師データになる。"
    },
    {
      title: "個人塾向け欠席連絡SaaS LP実験",
      description: "欠席連絡と振替候補をまとめる小型SaaSの需要をLPで測る。",
      experiment_type: "saas",
      market_category: "個人塾",
      acquisition_channel: "direct",
      expected_90d_profit_yen: 95_000,
      success_probability: 0.18,
      budget_yen: 500,
      estimated_work_minutes: 115,
      assumed_price_yen: 12_800,
      lp_word_count: 850,
      cta_count: 1,
      development_minutes: 90,
      feature_count: 3,
      rationale: "小規模運営者の作業削減に直結し、手動MVPで十分に検証できる。"
    },
    {
      title: "イベント主催者向け持ち物リマインドLP実験",
      description: "参加者への持ち物案内を自動化する訴求で、主催者の登録反応を測る。",
      experiment_type: "lp",
      market_category: "イベント主催者",
      acquisition_channel: "sns",
      expected_90d_profit_yen: 32_000,
      success_probability: 0.27,
      budget_yen: 0,
      estimated_work_minutes: 60,
      assumed_price_yen: 4_980,
      lp_word_count: 750,
      cta_count: 1,
      rationale: "LPだけで不便の強さを検証でき、開発前の教師データとして扱いやすい。"
    },
    {
      title: "地域別ペット可カフェディレクトリ検証",
      description: "ペット可カフェの地域特化ディレクトリを1カテゴリだけ作って検索とCTAを測る。",
      experiment_type: "directory_site",
      market_category: "ペット可店舗",
      acquisition_channel: "seo",
      expected_90d_profit_yen: 48_000,
      success_probability: 0.2,
      budget_yen: 0,
      estimated_work_minutes: 105,
      lp_word_count: 1_500,
      cta_count: 2,
      rationale: "地域検索と店舗DB型の相性を、小さいディレクトリで安く検証できる。"
    },
    {
      title: "採用担当向け面接質問AI LP実験",
      description: "職種ごとの面接質問作成をAIで補助する訴求をLPで検証する。",
      experiment_type: "ai_tool",
      market_category: "中小企業採用",
      acquisition_channel: "seo",
      expected_90d_profit_yen: 90_000,
      success_probability: 0.19,
      budget_yen: 300,
      estimated_work_minutes: 95,
      assumed_price_yen: 14_800,
      lp_word_count: 950,
      cta_count: 1,
      development_minutes: 60,
      feature_count: 2,
      rationale: "採用現場の作業負荷を下げる訴求で、AI自動化率と支払い意思を同時に測れる。"
    },
    {
      title: "町工場向け見積もり依頼整理LP実験",
      description: "見積もり依頼の不足情報を整理する簡易サービスのLP反応を測る。",
      experiment_type: "lp",
      market_category: "町工場",
      acquisition_channel: "direct",
      expected_90d_profit_yen: 70_000,
      success_probability: 0.18,
      budget_yen: 500,
      estimated_work_minutes: 90,
      assumed_price_yen: 19_800,
      lp_word_count: 850,
      cta_count: 1,
      rationale: "困り度が高いB2B領域を、営業前のLP反応で低コストにふるい分けられる。"
    }
  ].freeze

  def initialize(count: 10)
    @count = count
  end

  def call
    generation_run = create_generation_run!
    created_candidates = []

    CANDIDATE_SPECS.each do |attributes|
      break if created_candidates.size >= count
      next if active_duplicate_title?(attributes.fetch(:title))

      created_candidates << AicooLabExperimentCandidate.create!(
        attributes.merge(hypothesis_attributes_for(attributes), status: "proposed", generation_source: GENERATION_SOURCE)
      )
    end

    complete_generation_run!(generation_run, created_candidates)

    Result.new(created_candidates:, generation_run:)
  rescue StandardError => e
    fail_generation_run!(generation_run, e) if defined?(generation_run) && generation_run
    raise
  end

  private

  attr_reader :count

  def active_duplicate_title?(title)
    AicooLabExperimentCandidate.where(title:, status: ACTIVE_STATUSES).exists?
  end

  def hypothesis_attributes_for(attributes)
    market = attributes.fetch(:market_category)
    title = attributes.fetch(:title)

    {
      target_user: "#{market}で明確な作業負担や意思決定課題を持つ人",
      problem_statement: "#{market}向けに、#{attributes.fetch(:description)}という課題仮説がある。",
      hypothesis: "#{title}に対して一定のCTAまたはSignup反応があれば、90日利益仮説に進む価値がある。",
      validation_method: validation_method_for(attributes),
      expected_learning: "ターゲット、課題訴求、価格、獲得チャネル、初速のどこに勝ち筋があるかを学習する。",
      rejection_condition: "1000PV到達または90日経過時点でCTA率1%未満、かつSignupが0件なら棄却する。"
    }
  end

  def validation_method_for(attributes)
    case attributes.fetch(:experiment_type)
    when "seo", "directory_site"
      "検索流入ページを公開し、PV・CTAクリック・Signupを90日で測定する。"
    when "saas", "ai_tool"
      "LPと簡易フォームで事前登録を集め、必要なら手動運用MVPで支払い意思を確認する。"
    else
      "低コストLPを公開し、PV・CTAクリック・Signupを30日から90日で測定する。"
    end
  end

  def create_generation_run!
    AicooLabGenerationRun.create!(
      generation_type: "candidate_generation",
      prompt: generation_prompt,
      status: "running",
      started_at: Time.current,
      metadata: generation_metadata
    )
  end

  def complete_generation_run!(generation_run, created_candidates)
    generation_run.update!(
      response: generated_titles_response(created_candidates),
      status: "succeeded",
      generated_count: created_candidates.size,
      finished_at: Time.current
    )
  end

  def fail_generation_run!(generation_run, error)
    generation_run.update!(
      status: "failed",
      error_message: error.message,
      finished_at: Time.current
    )
  end

  def generation_prompt
    <<~PROMPT
      Rule based AICOO Lab candidate generation.
      Goal: generate low-cost experiment candidates that can become teacher data for AICOO predictions.
      Count: #{count}
      Budget rule: mostly 0-500 yen, low-cost first.
      Work rule: mostly 15-120 minutes.
      Candidate types: low-cost LP, SEO, SaaS validation, AI tool validation, directory site validation.
      Duplicate rule: skip existing titles with proposed, approved, or converted status.
    PROMPT
  end

  def generation_metadata
    {
      generator: self.class.name,
      generation_source: GENERATION_SOURCE,
      requested_count: count,
      candidate_spec_count: CANDIDATE_SPECS.size,
      active_duplicate_statuses: ACTIVE_STATUSES
    }
  end

  def generated_titles_response(created_candidates)
    created_candidates.map { |candidate| "- #{candidate.title}" }.join("\n")
  end
end
