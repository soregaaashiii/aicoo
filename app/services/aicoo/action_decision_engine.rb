module Aicoo
  class ActionDecisionEngine
    Candidate = Data.define(
      :action_key,
      :strategy_type,
      :asset_type,
      :concrete_task,
      :goal,
      :target,
      :target_type,
      :target_url_or_identifier,
      :execution_mode,
      :expected_profit_yen,
      :expected_hours,
      :success_probability,
      :historical_success_rate,
      :learning_value,
      :cost_yen,
      :risk,
      :implementation_complexity,
      :roi,
      :score,
      :reason,
      :execution_steps,
      :execution_units,
      :required_resources,
      :supporting_metrics
    ) do
      def to_metadata
        {
          "action_key" => action_key,
          "strategy_type" => strategy_type,
          "asset_type" => asset_type,
          "concrete_task" => concrete_task,
          "goal" => goal,
          "target" => target,
          "target_type" => target_type,
          "target_url_or_identifier" => target_url_or_identifier,
          "execution_mode" => execution_mode,
          "expected_profit_yen" => expected_profit_yen.to_i,
          "expected_hours" => expected_hours.to_d.to_s,
          "success_probability" => success_probability.to_d.to_s,
          "historical_success_rate" => historical_success_rate.to_d.to_s,
          "learning_value" => learning_value.to_i,
          "cost_yen" => cost_yen.to_i,
          "risk" => risk,
          "implementation_complexity" => implementation_complexity.to_i,
          "roi" => roi.to_d.to_s,
          "score" => score.to_d.to_s,
          "reason" => reason,
          "execution_steps" => execution_steps,
          "execution_units" => execution_units,
          "required_resources" => required_resources,
          "supporting_metrics" => supporting_metrics
        }.compact
      end
    end

    Decision = Data.define(:opportunity, :business_knowledge, :candidates, :selected) do
      def valid?
        selected.present? && selected.concrete_task.present? && selected.execution_units.any?
      end

      def concrete_task = selected&.concrete_task
      def goal = selected&.goal
      def target = selected&.target
      def target_type = selected&.target_type
      def target_url_or_identifier = selected&.target_url_or_identifier
      def execution_mode = selected&.execution_mode
      def execution_steps = selected&.execution_steps || []
      def execution_units = selected&.execution_units || []
      def expected_profit_yen = selected&.expected_profit_yen || opportunity.expected_value_yen
      def expected_hours = selected&.expected_hours || opportunity.expected_hours
      def success_probability = selected&.success_probability || opportunity.success_probability
      def cost_yen = selected&.cost_yen || 0

      def to_metadata
        ranked = Aicoo::UniversalAnalysisEngine::StrategyRanker.call(candidates)
        {
          "selected" => selected&.to_metadata,
          "candidate_count" => candidates.size,
          "candidates" => ranked.map.with_index(1) { |candidate, index| candidate.to_metadata.merge("rank" => index) },
          "strategy_ranking" => {
            "adopted" => selected&.to_metadata,
            "rejected" => ranked.reject { |candidate| candidate == selected }.map(&:to_metadata),
            "selection_reason" => selection_reason_for(ranked)
          },
          "business_knowledge" => business_knowledge.to_h
        }.compact
      end

      def selection_reason_for(ranked)
        return nil unless selected

        runner_up = ranked.find { |candidate| candidate != selected }
        return "#{selected.concrete_task} は比較対象内で期待値が最も高いため採用しました。" unless runner_up

        "#{selected.concrete_task} を採用。#{runner_up.concrete_task}（期待利益#{runner_up.expected_profit_yen.to_i}円）より、期待利益/工数/成功率を含む総合スコアが高いため。"
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(opportunity)
      @opportunity = opportunity
      @profile = Aicoo::BusinessCapabilityProfile.for(opportunity.business)
    end

    def call
      candidates = enumerate_candidates
      ranked = Aicoo::UniversalAnalysisEngine::StrategyRanker.call(candidates)
      Decision.new(
        opportunity:,
        business_knowledge: profile,
        candidates:,
        selected: ranked.first
      )
    end

    private

    attr_reader :opportunity, :profile

    def enumerate_candidates
      return [ search_intent_analysis_candidate ] if search_intent_analysis_required?
      return [ data_shortage_candidate ] if source_work_type == "data_shortage"

      profile.assets.flat_map do |asset|
        next unless asset_applicable?(asset)

        actions_for(asset).filter_map { |action| build_candidate(asset, action) }
      end.compact.select { |candidate| concrete_task_allowed?(candidate.concrete_task) }
    end

    def search_intent_analysis_candidate
      task = source_metadata["concrete_task"].presence || "「#{plain_target}」の検索意図と対応ページ要件を確認する"
      Candidate.new(
        action_key: "#{pattern}:search_intent_analysis",
        strategy_type: "search_intent_analysis",
        asset_type: "owner_tasks",
        concrete_task: task,
        goal: "改善対象ページが未確定のため、先に検索意図と受け皿を確定する",
        target: target_label,
        target_type: "search_query",
        target_url_or_identifier: target_identifier,
        execution_mode: "manual_operation",
        expected_profit_yen: opportunity.expected_value_yen,
        expected_hours: [ opportunity.expected_hours.to_d, 0.5.to_d ].max,
        success_probability: opportunity.success_probability,
        historical_success_rate: 0.5,
        learning_value: 60,
        cost_yen: 0,
        risk: "low",
        implementation_complexity: 2,
        roi: 0.to_d,
        score: opportunity.expected_value_yen.to_d + 60,
        reason: opportunity.reason,
        execution_steps: [
          "GSCで対象クエリの表示回数・クリック・現在の流入先を確認する",
          "自社内に対応ページが存在するか確認する",
          "SERPは参考として検索意図を分類する",
          "既存改善・新規記事・新規LP・新規カテゴリのどれにするか決める",
          "次のActionCandidate用に判断理由を記録する"
        ],
        execution_units: [ {
          "label" => task,
          "target_amount" => 1,
          "estimated_minutes" => 30,
          "reason" => opportunity.reason,
          "target_type" => "search_query",
          "target_identifier" => target_identifier
        } ],
        required_resources: source_metadata.slice("work_type", "page_exists", "matched_page", "recommended_slug", "creation_type"),
        supporting_metrics: opportunity.supporting_metrics.to_h.deep_stringify_keys
      )
    end

    def data_shortage_candidate
      task = source_metadata["concrete_task"].presence || "#{target_label}の改善判断に必要なデータを確認する"
      Candidate.new(
        action_key: "#{pattern}:data_shortage",
        strategy_type: "data_shortage",
        asset_type: "owner_tasks",
        concrete_task: task,
        goal: "改善対象を決めるための計測・内部データを揃える",
        target: target_label,
        target_type: "data_check",
        target_url_or_identifier: target_identifier,
        execution_mode: "data_operation",
        expected_profit_yen: opportunity.expected_value_yen,
        expected_hours: [ opportunity.expected_hours.to_d, 0.5.to_d ].max,
        success_probability: opportunity.success_probability,
        historical_success_rate: 0.5,
        learning_value: 55,
        cost_yen: 0,
        risk: "low",
        implementation_complexity: 2,
        roi: 0.to_d,
        score: opportunity.expected_value_yen.to_d + 55,
        reason: opportunity.reason,
        execution_steps: [
          "不足しているGSC/GA4/内部データを確認する",
          "改善対象ページを特定できるデータがあるか確認する",
          "不足している計測・紐付けを記録する"
        ],
        execution_units: [ {
          "label" => task,
          "target_amount" => 1,
          "estimated_minutes" => 30,
          "reason" => opportunity.reason,
          "target_type" => "data_check",
          "target_identifier" => target_identifier
        } ],
        required_resources: source_metadata.slice("work_type", "page_exists", "matched_page", "recommended_slug", "creation_type"),
        supporting_metrics: opportunity.supporting_metrics.to_h.deep_stringify_keys
      )
    end

    def asset_applicable?(asset)
      case pattern
      when "demand_without_asset", "demand_without_supply", "asset_missing"
        asset.can_create
      when "high_impression_low_ctr", "rank_11_20_gap", "near_win_position",
           "traffic_without_conversion", "high_traffic_low_conversion", "funnel_drop",
           "asset_without_traffic", "weak_existing_asset", "activity_gap", "data_quality_gap",
           "supply_gap", "verification_gap", "engagement_signal"
        asset.can_update || asset.can_create
      else
        asset.can_update || asset.can_create
      end
    end

    def build_candidate(asset, action)
      hours = candidate_hours(asset, action)
      profit = candidate_profit(asset)
      success = candidate_success(asset)
      learning = learning_value_for(asset)
      cost = asset.cost_yen.to_i
      risk = risk_for(asset)
      complexity = implementation_complexity_for(asset, action)
      roi = cost.positive? ? (profit.to_d / cost.to_d).round(2) : 0.to_d
      score = ((profit.to_d / [ hours.to_d, 0.1.to_d ].max) * success.to_d * risk_multiplier(risk)) +
        (learning.to_d * 0.4) - cost - complexity

      Candidate.new(
        action_key: "#{pattern}:#{asset.asset_type}:#{action.fetch(:strategy_type)}",
        strategy_type: action.fetch(:strategy_type),
        asset_type: asset.asset_type,
        concrete_task: action.fetch(:task),
        goal: action.fetch(:goal),
        target: target_label,
        target_type: action.fetch(:target_type),
        target_url_or_identifier: target_identifier,
        execution_mode: action.fetch(:execution_mode),
        expected_profit_yen: profit,
        expected_hours: hours,
        success_probability: success,
        historical_success_rate: asset.historical_success_rate,
        learning_value: learning,
        cost_yen: cost,
        risk:,
        implementation_complexity: complexity,
        roi:,
        score:,
        reason: opportunity.reason,
        execution_steps: action.fetch(:steps),
        execution_units: execution_units_for(action, hours),
        required_resources: action.fetch(:required_resources, {}).merge("asset_type" => asset.asset_type),
        supporting_metrics: opportunity.supporting_metrics.to_h.deep_stringify_keys
      )
    end

    def actions_for(asset)
      case pattern
      when "demand_without_asset", "demand_without_supply", "asset_missing"
        demand_actions(asset)
      when "high_impression_low_ctr"
        ctr_actions(asset)
      when "rank_11_20_gap", "near_win_position"
        rank_gap_actions(asset)
      when "traffic_without_conversion", "high_traffic_low_conversion", "funnel_drop"
        conversion_actions(asset)
      when "asset_without_traffic", "weak_existing_asset", "engagement_signal"
        asset_traffic_actions(asset)
      when "supply_gap"
        supply_gap_actions(asset)
      when "verification_gap"
        verification_gap_actions(asset)
      when "activity_gap"
        activity_gap_actions(asset)
      when "data_quality_gap"
        data_quality_actions(asset)
      else
        generic_actions(asset)
      end
    end

    def demand_actions(asset)
      case asset.asset_type
      when "articles"
        [ content_action(
          strategy_type: "article_creation",
          task: "「#{plain_target}」向けの記事を1本作成する",
          goal: "需要がある検索テーマに対応する記事入口を作る",
          target_type: "article",
          steps: %w[タイトル決定 記事構成作成 記事作成 内部リンク追加 公開]
        ) ]
      when "comparison_pages"
        return [] unless comparison_intent?

        [ content_action(
          strategy_type: "comparison_page_creation",
          task: "「#{plain_target}」向けの比較ページを1本作成する",
          goal: "比較検討中のユーザーに対応する受け皿を作る",
          target_type: "comparison_page",
          steps: %w[比較軸決定 ページ構成作成 比較表追加 内部リンク追加 公開]
        ) ]
      when "landing_pages"
        [ code_action(
          strategy_type: "landing_page_creation",
          task: "「#{plain_target}」向けLPを1本作成する",
          goal: "需要があるテーマに対応するLPを作る",
          target_type: "landing_page",
          steps: %w[LP構成決定 ファーストビュー作成 CTA追加 公開 計測確認]
        ) ]
      when "faq"
        [ content_action(
          strategy_type: "faq_creation",
          task: "「#{plain_target}」に対応するFAQを追加する",
          goal: "需要がある疑問に短い回答資産を作る",
          target_type: "faq",
          steps: %w[質問選定 回答案作成 関連ページへ追加 公開]
        ) ]
      when "area_pages", "category_pages"
        [ content_action(
          strategy_type: "category_entry_creation",
          task: "「#{plain_target}」に対応するカテゴリ入口を1件作成する",
          goal: "需要テーマへ遷移できる分類入口を作る",
          target_type: asset.asset_type.singularize,
          steps: %w[分類名決定 対象資産整理 ページ作成 内部リンク追加 公開]
        ) ]
      when "internal_links"
        [ content_action(
          strategy_type: "internal_link_addition",
          task: "「#{plain_target}」への内部リンクを3件追加する",
          goal: "既存資産から需要テーマへの導線を作る",
          target_type: "internal_links",
          steps: %w[リンク元選定 アンカーテキスト決定 内部リンク追加 公開]
        ) ]
      when "listings"
        [ {
          strategy_type: "data_addition",
          task: "#{plain_target}に関連する掲載データを20件追加する",
          goal: "需要テーマに対応するデータ量を増やす",
          target_type: "listing_data",
          execution_mode: "data_operation",
          steps: %w[対象条件決定 データ収集 重複確認 登録 ActionResult登録],
          required_resources: {}
        } ]
      else
        []
      end
    end

    def supply_gap_actions(asset)
      case asset.asset_type
      when "listings"
        [ {
          strategy_type: "supply_addition",
          task: "#{plain_target}に関連する掲載データを20件追加する",
          goal: "需要に対して不足している供給資産を増やす",
          target_type: "listing_data",
          execution_mode: "data_operation",
          steps: %w[対象条件決定 データ収集 重複確認 登録 ActionResult登録],
          required_resources: {}
        } ]
      when "articles", "area_pages", "category_pages"
        demand_actions(asset)
      else
        []
      end
    end

    def verification_gap_actions(asset)
      return [] unless %w[listings owner_tasks].include?(asset.asset_type)

      [ {
        strategy_type: "quality_verification",
        task: "#{plain_target}に関連する未確認データを15件確認する",
        goal: "品質確認済み資産を増やしてCV意図の強い流入に応える",
        target_type: "quality_asset",
        execution_mode: "manual_operation",
        steps: %w[対象一覧取得 情報確認 更新 ActionResult登録],
        required_resources: {}
      } ]
    end

    def ctr_actions(asset)
      return [] unless %w[articles landing_pages comparison_pages area_pages category_pages faq cta internal_links].include?(asset.asset_type)

      [
        content_action(
          strategy_type: "title_improvement",
          task: "#{target_label}のタイトルを#{target_amount}件改善する",
          goal: "表示回数がある入口のクリック理由をタイトルで明確にする",
          target_type: "traffic_entry",
          steps: %w[対象ページ確認 検索クエリ確認 タイトル修正 公開]
        ),
        content_action(
          strategy_type: "meta_improvement",
          task: "#{target_label}のmeta descriptionを#{target_amount}件改善する",
          goal: "検索結果での補足訴求を強めてCTRを上げる",
          target_type: "traffic_entry",
          steps: %w[対象ページ確認 検索意図確認 meta修正 公開]
        ),
        content_action(
          strategy_type: "faq_addition",
          task: "#{target_label}にFAQを#{[ target_amount.to_i, 3 ].max}件追加する",
          goal: "検索意図に対応する回答を増やしてクリック後の満足度を上げる",
          target_type: "faq",
          steps: %w[質問選定 回答案作成 FAQ追加 公開]
        ),
        content_action(
          strategy_type: "internal_link_addition",
          task: "#{target_label}へ内部リンクを#{[ target_amount.to_i, 5 ].max}件追加する",
          goal: "関連資産から対象入口の評価と流入を補強する",
          target_type: "internal_links",
          steps: %w[リンク元選定 アンカーテキスト決定 内部リンク追加 公開]
        )
      ]
    end

    def rank_gap_actions(asset)
      return [] unless %w[articles comparison_pages faq internal_links area_pages category_pages].include?(asset.asset_type)

      [
        content_action(
          strategy_type: "serp_gap_response",
          task: "#{target_label}の順位改善要素を1件追加する",
          goal: "順位11〜20位の入口に内部データで不足が見える要素を追加する",
          target_type: "page_or_query",
          steps: %w[不足要素確認 FAQまたは比較要素追加 内部リンク追加 公開 順位確認メモ作成]
        ),
        content_action(
          strategy_type: "comparison_element_addition",
          task: "#{target_label}に比較要素を1件追加する",
          goal: "競合上位にある比較要素を補って上位化余地を作る",
          target_type: "comparison_element",
          steps: %w[競合要素確認 比較軸選定 比較要素追加 公開]
        ),
        content_action(
          strategy_type: "guide_article_addition",
          task: "「#{plain_target}」向けのガイド記事を1本作成する",
          goal: "順位差分を補う関連入口を作る",
          target_type: "article",
          steps: %w[ガイド構成決定 記事作成 内部リンク追加 公開]
        )
      ]
    end

    def conversion_actions(asset)
      return [] unless %w[cta internal_links signup checkout pricing landing_pages listings].include?(asset.asset_type)

      [
        code_action(
          strategy_type: "cta_addition",
          task: "流入上位#{target_amount}ページに#{conversion_label}導線を追加する",
          goal: "流入をCVに近い行動へつなげる",
          target_type: "conversion_path",
          steps: %w[対象ページ選定 CTA位置決定 CTA追加 イベント計測確認 ActionResult登録]
        ),
        content_action(
          strategy_type: "internal_link_addition",
          task: "流入上位#{target_amount}ページからCV近接ページへ内部リンクを追加する",
          goal: "既存流入からCVに近いページへの回遊を作る",
          target_type: "internal_links",
          steps: %w[流入上位ページ確認 リンク先選定 内部リンク追加 公開]
        )
      ]
    end

    def asset_traffic_actions(asset)
      return [] unless %w[internal_links articles landing_pages comparison_pages area_pages category_pages].include?(asset.asset_type)

      [
        content_action(
          strategy_type: "internal_link_addition",
          task: "#{target_label}への内部リンクを3件追加する",
          goal: "作成済み資産に流入と回遊を作る",
          target_type: "asset",
          steps: %w[対象資産確認 リンク元選定 内部リンク追加 公開 クリック確認メモ作成]
        ),
        content_action(
          strategy_type: "intro_improvement",
          task: "#{target_label}の冒頭に結論と関連導線を1件追加する",
          goal: "流入後すぐに次の行動理由を提示する",
          target_type: "asset",
          steps: %w[対象資産確認 冒頭改善 関連導線追加 公開]
        )
      ]
    end

    def activity_gap_actions(asset)
      return [] if asset.asset_type.in?(%w[signup checkout pricing]) && !asset.can_update

      [ {
        strategy_type: "small_improvement",
        task: "#{asset_label(asset)}の改善を1件実行する",
        goal: "止まっている改善サイクルを再開する",
        target_type: "operation",
        execution_mode: "manual_operation",
        steps: %w[対象選定 小さな改善実行 Activity記録 ActionResult登録],
        required_resources: {}
      } ]
    end

    def data_quality_actions(asset)
      return [] unless %w[cta signup checkout landing_pages pricing owner_tasks].include?(asset.asset_type)

      [ code_action(
        strategy_type: "measurement_check",
        task: "#{asset_label(asset)}の計測設定を確認する",
        goal: "成果判断に必要なデータを揃える",
        target_type: "measurement",
        steps: %w[不足項目確認 設定確認 テスト取得 エラー記録 次Action作成]
      ) ]
    end

    def generic_actions(asset)
      return [] unless asset.can_update || asset.can_create

      [ {
        strategy_type: "generic_improvement",
        task: "#{target_label}に対して#{asset_label(asset)}の改善を1件実行する",
        goal: "検出された改善機会を実行可能な作業に変える",
        target_type: "task",
        execution_mode: execution_mode_for_asset(asset),
        steps: %w[対象確認 作業実行 結果確認 ActionResult登録],
        required_resources: {}
      } ]
    end

    def content_action(strategy_type:, task:, goal:, target_type:, steps:)
      {
        strategy_type:,
        task:,
        goal:,
        target_type:,
        execution_mode: "content_creation",
        steps:,
        required_resources: {}
      }
    end

    def code_action(strategy_type:, task:, goal:, target_type:, steps:)
      {
        strategy_type:,
        task:,
        goal:,
        target_type:,
        execution_mode: "code_revision",
        steps:,
        required_resources: {}
      }
    end

    def execution_units_for(action, hours)
      [
        {
          "label" => action.fetch(:task),
          "target_amount" => target_amount,
          "estimated_minutes" => (hours.to_d * 60).round,
          "reason" => opportunity.reason,
          "target_type" => action.fetch(:target_type),
          "target_identifier" => target_identifier
        }.compact
      ]
    end

    def pattern = opportunity.opportunity_type.to_s

    def target_hash
      @target_hash ||= opportunity.target.to_h.deep_stringify_keys
    end

    def source_metadata
      @source_metadata ||= opportunity.source_issue.metadata.to_h.deep_stringify_keys
    end

    def source_work_type
      source_metadata["work_type"].presence ||
        source_metadata["creation_type"].presence ||
        opportunity.required_resources.to_h.deep_stringify_keys["work_type"].presence ||
        opportunity.required_resources.to_h.deep_stringify_keys["creation_type"].presence
    end

    def search_intent_analysis_required?
      return true if source_work_type == "search_intent_analysis"
      return true if opportunity.source_issue.action_type.to_s == "opportunity_validation"

      plain_target.match?(/#{Regexp.escape(opportunity.business.name.to_s)}.*(比較|とは|違い|評判|口コミ|おすすめ|使い方|サービス)/)
    end

    def target_label
      target_hash["label"].presence || target_hash["query"].presence || target_hash["page_path"].presence || opportunity.source_issue.title
    end

    def plain_target
      target_label.to_s.delete_prefix("「").delete_suffix("」")
    end

    def target_identifier
      target_hash["page_path"].presence || target_hash["query"].presence || target_hash["label"].presence || plain_target
    end

    def target_amount
      target_hash["amount"].presence || opportunity.source_issue.quantity.presence || 1
    end

    def comparison_intent?
      plain_target.match?(/比較|違い|料金|compare|versus|vs/i)
    end

    def conversion_label
      events = Array(opportunity.required_resources.to_h.dig("conversion_events")).presence ||
        Array(profile.conversion_events)
      events.first.presence || "CV"
    end

    def candidate_hours(asset, action)
      base_minutes = asset.estimated_minutes.to_i
      expected_minutes = (opportunity.expected_hours.to_d * 60).round
      minutes = [ base_minutes, expected_minutes ].compact.max
      minutes = 30 if minutes.zero?
      (minutes.to_d / 60).round(2)
    end

    def candidate_profit(asset)
      (opportunity.expected_value_yen.to_d * asset.expected_roi.to_d).round
    end

    def candidate_success(asset)
      ((opportunity.success_probability.to_d + asset.historical_success_rate.to_d) / 2).round(2)
    end

    def learning_value_for(asset)
      confidence_gap = [ 100 - opportunity.confidence.to_i, 0 ].max
      novelty = asset.required_data.any? { |source| !Array(opportunity.supporting_metrics.to_h["source"]).include?(source) } ? 10 : 0
      [ confidence_gap / 2 + novelty, 80 ].min
    end

    def risk_for(asset)
      return "medium" if asset.cost_yen.to_i.positive?
      return "medium" if %w[checkout pricing].include?(asset.asset_type)

      "low"
    end

    def risk_multiplier(risk)
      { "low" => 1.0.to_d, "medium" => 0.85.to_d, "high" => 0.6.to_d }.fetch(risk, 0.8.to_d)
    end

    def implementation_complexity_for(asset, action)
      base = (asset.estimated_minutes.to_i / 15).clamp(1, 20)
      mode_penalty = {
        "manual_operation" => 2,
        "content_creation" => 3,
        "data_operation" => 4,
        "code_revision" => 5
      }.fetch(action.fetch(:execution_mode), 3)
      base + mode_penalty
    end

    def execution_mode_for_asset(asset)
      case asset.asset_type
      when "listings"
        "data_operation"
      when "articles", "comparison_pages", "faq", "area_pages", "category_pages"
        "content_creation"
      when "owner_tasks"
        "manual_operation"
      else
        "code_revision"
      end
    end

    ABSTRACT_PATTERNS = [
      /要具体化/,
      /検索需要があるテーマ/,
      /CVを改善/,
      /CV改善\z/,
      /SEO改善\z/,
      /SEOを改善/,
      /UXを改善/,
      /CTAを改善/,
      /デザインを改善/,
      /サイト改善/,
      /導線改善/,
      /TODOを具体化/,
      /記事を増やす/,
      /Analyzer/i
    ].freeze

    def concrete_task_allowed?(text)
      Aicoo::UniversalAnalysisEngine::ConcreteTodoBuilder.call(summary: text).valid?
    end

    def asset_label(asset)
      {
        "articles" => "記事",
        "listings" => "掲載データ",
        "area_pages" => "エリアページ",
        "category_pages" => "カテゴリページ",
        "landing_pages" => "LP",
        "comparison_pages" => "比較ページ",
        "faq" => "FAQ",
        "cta" => "CTA",
        "internal_links" => "内部リンク",
        "signup" => "登録導線",
        "checkout" => "購入導線",
        "pricing" => "料金訴求",
        "owner_tasks" => "手作業"
      }.fetch(asset.asset_type, asset.asset_type)
    end
  end
end
