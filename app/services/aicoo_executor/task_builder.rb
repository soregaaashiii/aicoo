module AicooExecutor
  class TaskBuilder
    def self.from_revenue_execution(revenue_execution)
      new(revenue_execution:).call
    end

    def self.from_action_candidate(action_candidate)
      new(action_candidate:).call_from_action_candidate
    end

    def initialize(revenue_execution: nil, action_candidate: nil)
      @revenue_execution = revenue_execution
      @source_record = action_candidate || revenue_execution.source_record
    end

    def call
      AicooExecutorTask.create!(
        title: task_title,
        source_type: executor_source_type,
        source_id: revenue_execution.source_id,
        execution_type:,
        execution_prompt:,
        estimated_minutes:,
        status: "approval_pending"
      )
    end

    def call_from_action_candidate
      existing_task = AicooExecutorTask.unfinished_for_action_candidate(source_record)
      return existing_task if existing_task

      AicooExecutorTask.create!(
        title: task_title,
        source_type: "action_candidate",
        source_id: source_record.id,
        execution_type:,
        execution_prompt: source_record.execution_prompt.presence || execution_prompt,
        estimated_minutes:,
        status: "approved",
        approved_at: Time.current
      )
    end

    private

    attr_reader :revenue_execution, :source_record

    def task_title
      "実行計画: #{source_title}"
    end

    def source_title
      source_record&.title || revenue_execution.title
    end

    def source_description
      [
        source_record&.try(:description),
        source_record&.try(:rationale),
        source_record&.try(:notes)
      ].compact_blank.join("\n\n")
    end

    def executor_source_type
      {
        "candidate" => "lab_candidate",
        "experiment" => "lab_experiment",
        "action_candidate" => "action_candidate"
      }.fetch(revenue_execution.source_type)
    end

    def execution_type
      return "shop_import" if shop_import?
      return "lp_creation" if lp_creation?
      return "seo_update" if seo_update?
      return "seo_content" if seo_content?
      return "market_research" if market_research?
      return "customer_interview" if customer_interview?
      return "data_preparation" if data_preparation?
      return "data_collection" if data_collection?

      "custom"
    end

    def execution_prompt
      case execution_type
      when "shop_import"
        shop_import_prompt
      when "lp_creation"
        lp_creation_prompt
      when "seo_content"
        seo_content_prompt
      when "seo_update"
        seo_update_prompt
      when "market_research"
        market_research_prompt
      when "customer_interview"
        customer_interview_prompt
      when "data_preparation"
        data_preparation_prompt
      when "data_collection"
        data_collection_prompt
      else
        custom_prompt
      end
    end

    def estimated_minutes
      if source_record&.respond_to?(:estimated_work_minutes) && source_record.estimated_work_minutes.present?
        source_record.estimated_work_minutes
      elsif source_record&.respond_to?(:expected_hours) && source_record.expected_hours.present?
        (source_record.expected_hours.to_d * 60).round
      else
        revenue_execution&.estimated_work_minutes.to_i
      end
    end

    def source_action_type
      source_record&.try(:action_type).to_s
    end

    def source_experiment_type
      source_record&.try(:experiment_type).to_s
    end

    def searchable_text
      [
        source_title,
        source_description,
        source_action_type,
        source_experiment_type,
        source_record&.try(:execution_prompt)
      ].compact.join(" ").downcase
    end

    def shop_import?
      source_action_type == "shop_import" ||
        searchable_text.match?(/shop_import|店舗|店鋪|import|インポート|追加/)
    end

    def lp_creation?
      %w[build_lp lp].include?(source_action_type) ||
        %w[lp market_test].include?(source_experiment_type) ||
        searchable_text.match?(/lp|ランディング|事前登録/)
    end

    def seo_content?
      source_action_type == "seo_article" ||
        source_experiment_type == "seo" ||
        searchable_text.match?(/seo|記事|コンテンツ/)
    end

    def seo_update?
      source_action_type == "seo_improvement" ||
        searchable_text.match?(/リライト|内部リンク|更新|改善/)
    end

    def market_research?
      %w[market_research serp_research].include?(source_action_type) ||
        searchable_text.match?(/市場調査|serp|競合|調査/)
    end

    def customer_interview?
      searchable_text.match?(/インタビュー|ヒアリング|顧客/)
    end

    def data_collection?
      searchable_text.match?(/データ|収集|gsc|ga4|csv/)
    end

    def data_preparation?
      source_action_type == "data_preparation" ||
        source_record&.try(:metadata).to_h["metric_rule"] == "correction_readiness" ||
        searchable_text.match?(/judge補正|不足データ|actionresult|businessmetricdaily|revenueevent/)
    end

    def shop_import_prompt
      codex_prompt(
        purpose: "吸えログへ店舗を追加し、検索流入や回遊の受け皿になる店舗データを増やす。",
        scope: [
          "対象タスク: #{source_title}",
          "店舗追加、重複チェック、喫煙情報の確認、登録後の表示確認までを扱う。"
        ],
        protected_items: [
          "既存店舗データを破壊・上書きしないこと。既存データ破壊禁止。",
          "重複店舗を作らないこと。",
          "喫煙情報は不明な場合に断定せず、確認元や未確認であることを明示すること。"
        ],
        steps: [
          "対象エリア・対象店舗数・登録条件を整理する。",
          "既存店舗と名称・住所・電話番号で重複チェックする。",
          "住所、営業時間、電話番号、喫煙可否、公式URLなど必要項目を集める。",
          "店舗データを追加し、既存一覧や詳細表示が壊れていないか確認する。",
          "追加件数、重複除外件数、不明項目をまとめる。"
        ],
        report_items: [
          "追加した店舗数と重複で除外した店舗数",
          "喫煙情報が未確認の店舗",
          "確認した画面やコマンド"
        ]
      )
    end

    def lp_creation_prompt
      codex_prompt(
        purpose: "LPを作成し、事前登録や問い合わせの反応をpreview上で検証できる状態にする。",
        scope: [
          "対象タスク: #{source_title}",
          "ターゲット: #{source_record&.try(:target_user).presence || source_record&.try(:market_category).presence || "未設定"}",
          "headline、subheadline、本文、CTA、preview確認までを扱う。"
        ],
        protected_items: [
          "本番公開しないこと。",
          "既存のCTA計測、PV計測、Signup計測を壊さないこと。CTA計測を壊さない。",
          "既存LPや既存実験のpreview_slugを変更しないこと。"
        ],
        steps: [
          "目的、ターゲット、訴求する課題を1つに絞る。",
          "headline、subheadline、本文、CTA文言を作る。",
          "previewで表示できる状態にし、本番公開は行わない。",
          "CTAクリックとSignup導線が既存の計測ルートに沿っているか確認する。",
          "PCとスマホ幅で本文やボタンが崩れていないか確認する。"
        ],
        report_items: [
          "作成または編集したLP",
          "preview URL",
          "CTA計測を壊していないことの確認結果"
        ]
      )
    end

    def seo_content_prompt
      codex_prompt(
        purpose: "SEO記事を作成または改善し、検索意図に合う流入導線を増やす。",
        scope: [
          "対象タスク: #{source_title}",
          "記事作成/改善、SEOタイトル、meta description、見出し、内部リンク、CTAを扱う。"
        ],
        protected_items: [
          "既存記事を壊さないこと。",
          "既存URLや既存導線を不用意に変更しないこと。",
          "根拠のない断定や検索意図から外れた本文を追加しないこと。"
        ],
        steps: [
          "検索意図と読者の困りごとを整理する。",
          "SEOタイトルとmeta descriptionを作る。",
          "見出し構成を作り、本文を作成または改善する。",
          "関連する既存記事への内部リンクと、必要なCTAを追加する。",
          "既存記事の表示、リンク切れ、レイアウト崩れがないか確認する。"
        ],
        report_items: [
          "作成・改善したSEOタイトルとmeta description",
          "追加した内部リンク",
          "既存記事を壊していないことの確認結果"
        ]
      )
    end

    def seo_update_prompt
      codex_prompt(
        purpose: "既存SEOページを更新し、順位低下やCVR低下を防ぎながら検索意図への一致度を上げる。",
        scope: [
          "対象タスク: #{source_title}",
          "既存記事更新、変更前後の明示、既存URL維持、内部リンク改善を扱う。"
        ],
        protected_items: [
          "既存URL維持。URL、slug、canonicalを不用意に変更しないこと。",
          "既存記事を壊さないこと。",
          "変更前後が分からない大規模な書き換えを避けること。"
        ],
        steps: [
          "既存ページの目的、流入キーワード、足りない情報を確認する。",
          "変更前後が分かるように、改善対象の見出しや本文を整理する。",
          "見出し、本文、内部リンク、CTAを必要最小限で更新する。",
          "既存URL維持とリンク切れがないことを確認する。",
          "更新内容と狙いをまとめる。"
        ],
        report_items: [
          "変更前後の要点",
          "維持した既存URL",
          "確認した内部リンクとCTA"
        ]
      )
    end

    def market_research_prompt
      codex_prompt(
        purpose: "市場調査を構造化し、収益性と次に取るべき行動を判断できる材料を作る。",
        scope: [
          "対象タスク: #{source_title}",
          "競合、検索結果、価格帯、困り度、収益性、次アクション候補を扱う。"
        ],
        protected_items: [
          "根拠のない市場規模や売上見込みを断定しないこと。",
          "調査結果と推測を混同しないこと。",
          "既存機能や既存データを変更しないこと。"
        ],
        steps: [
          "調査対象、顧客、課題、代替手段を定義する。",
          "競合、価格帯、獲得チャネル、検索需要を調べる。",
          "根拠URL、観測事実、推測を分けて整理する。",
          "困り度、収益性、競合強度、初速を評価する。",
          "次アクション候補を3件以上出す。"
        ],
        report_items: [
          "構造化した調査結果",
          "根拠と推測の区別",
          "次アクション候補"
        ]
      )
    end

    def customer_interview_prompt
      codex_prompt(
        purpose: "顧客インタビューを設計し、仮説検証に必要な質問と記録フォーマットを作る。",
        scope: [
          "対象タスク: #{source_title}",
          "質問リスト、仮説検証観点、対象者条件、記録フォーマットを扱う。"
        ],
        protected_items: [
          "誘導質問だけで構成しないこと。",
          "個人情報を必要以上に集めないこと。",
          "既存機能や既存データを変更しないこと。"
        ],
        steps: [
          "検証したい仮説を明文化する。",
          "対象者条件と除外条件を整理する。",
          "質問リストを10個以上作る。",
          "回答を記録するフォーマットを作る。",
          "インタビュー後に継続・修正・中止を判断する基準を作る。"
        ],
        report_items: [
          "仮説検証観点",
          "質問リスト",
          "記録フォーマット"
        ]
      )
    end

    def data_collection_prompt
      codex_prompt(
        purpose: "判断材料になるデータを取得・整理し、次の評価や実験判断に使える形で保存する。",
        scope: [
          "対象タスク: #{source_title}",
          "データ取得、保存先、加工形式、既存データ上書き禁止の確認を扱う。"
        ],
        protected_items: [
          "既存データ上書き禁止。",
          "取得元や保存先を確認せずに本番データを変更しないこと。",
          "外部APIや外部サービスに送信する場合は事前確認すること。"
        ],
        steps: [
          "必要データ、取得元、保存先を整理する。",
          "既存データを上書きしない保存方法を選ぶ。",
          "CSV、TXT、JSONなど再利用しやすい形式に整える。",
          "件数、期間、欠損、異常値を確認する。",
          "次にAIや人間が評価しやすい要約を作る。"
        ],
        report_items: [
          "取得したデータの保存先",
          "取得件数と対象期間",
          "既存データ上書き禁止を守った確認結果"
        ]
      )
    end

    def data_preparation_prompt
      codex_prompt(
        purpose: "Judge補正やproxy_score補正に必要な不足データを埋め、AICOOの予測精度を改善できる状態にする。",
        scope: [
          "対象タスク: #{source_title}",
          "背景: #{source_description.presence || "不足データの整理"}",
          "ActionResult、BusinessMetricDaily、RevenueEventの不足確認と記録を扱う。"
        ],
        protected_items: [
          "db:drop / db:reset / drop database は絶対禁止。",
          "既存データを上書き・削除しないこと。",
          "推測で実績値を入力しないこと。根拠がない場合はnoteに未確認と残すこと。"
        ],
        steps: [
          "対象Businessの不足データ種別と必要数/現在数を確認する。",
          "実行済みActionCandidateがあればActionResultを記録する。",
          "BusinessMetricDailyが不足していれば、既存DataHub/Analytics/手入力データから不足日分を取り込む。",
          "売上・費用が発生していればRevenueEventを記録する。",
          "Daily Runまたは関連確認コマンドで補正できない理由が減ったか確認する。"
        ],
        report_items: [
          "追加・更新したActionResult件数",
          "追加・更新したBusinessMetricDaily日数",
          "追加・更新したRevenueEvent件数",
          "まだ不足しているデータと理由"
        ]
      )
    end

    def custom_prompt
      codex_prompt(
        purpose: "次の行動を、Codexに依頼できる実行可能なタスクへ分解する。",
        scope: [
          "対象タスク: #{source_title}",
          "背景: #{source_description.presence || "未設定"}",
          "汎用テンプレートとして、調査・実装・確認・報告までを扱う。"
        ],
        protected_items: [
          "作業範囲外の大きな仕様変更をしないこと。",
          "既存機能を壊さないこと。",
          "破壊的なDB操作をしないこと。"
        ],
        steps: [
          "目的と完了条件を確認する。",
          "必要なファイル、画面、データを調べる。",
          "最小の変更で実行する。",
          "影響範囲に合った確認コマンドを実行する。",
          "変更内容、確認結果、残課題をまとめる。"
        ],
        report_items: [
          "実行した作業",
          "変更ファイル",
          "確認コマンドと結果"
        ]
      )
    end

    def codex_prompt(purpose:, scope:, protected_items:, steps:, report_items:)
      <<~PROMPT
        # AICOO Executor 実行指示

        ## 目的
        #{purpose}

        ## 対象
        #{format_lines(scope)}

        ## 作業範囲
        - このプロンプトに書かれた対象タスクの実行計画に沿って作業する。
        - 必要な調査、実装、確認、完了報告までを行う。
        - 自動実行、外部公開、課金、広告出稿は行わない。

        ## 絶対に壊してはいけないもの
        - 既存機能を壊さないこと。
        - db:drop / db:reset / drop database は絶対禁止。
        - ユーザーが明示していない既存データの削除・上書き・リセットをしないこと。
        #{format_lines(protected_items)}

        ## 実装手順
        #{format_numbered_lines(steps)}

        ## 確認コマンド
        - bin/rails zeitwerk:check
        - bin/rails test
        - bundle exec rubocop

        ## 完了報告に含めるもの
        #{format_lines(report_items)}
        - 実行した確認コマンドと結果
        - 実施しなかったこと、未確認事項、次に人間が判断すべきこと
      PROMPT
    end

    def format_lines(lines)
      lines.map { |line| "- #{line}" }.join("\n")
    end

    def format_numbered_lines(lines)
      lines.each_with_index.map { |line, index| "#{index + 1}. #{line}" }.join("\n")
    end
  end
end
