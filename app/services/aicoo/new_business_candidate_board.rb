module Aicoo
  class NewBusinessCandidateBoard
    Row = Data.define(
      :rank,
      :action_candidate,
      :business,
      :title,
      :problem,
      :target_customer,
      :revenue_model,
      :expected_profit_yen,
      :expected_hourly_value_yen,
      :initial_cost_yen,
      :expected_hours,
      :validation_step,
      :source_query,
      :market_memo,
      :reason,
      :status
    )
    Result = Data.define(
      :candidates,
      :top_candidates,
      :today_count,
      :pending_count,
      :approved_count,
      :zero_reasons
    )

    NEW_BUSINESS_ACTION_TYPES = %w[new_business lp_experiment market_test build_lp build_mvp market_research opportunity_validation].freeze
    PENDING_STATUSES = %w[idea pending].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(limit: 10, today: Time.zone.today)
      @limit = limit
      @today = today
    end

    def call
      rows = candidate_scope.limit(limit).map.with_index(1) { |candidate, index| row_for(candidate, index) }
      Result.new(
        candidates: rows,
        top_candidates: rows.first(5),
        today_count: candidate_base.where(created_at: today.all_day).count,
        pending_count: candidate_base.where(status: PENDING_STATUSES).count,
        approved_count: candidate_base.where(status: "approved").count,
        zero_reasons: rows.empty? ? zero_reasons : []
      )
    end

    private

    attr_reader :limit, :today

    def candidate_scope
      candidate_base
        .active_for_ranking
        .order(Arel.sql("final_score DESC NULLS LAST, expected_hourly_value_yen DESC NULLS LAST, expected_profit_yen DESC NULLS LAST, created_at DESC"))
    end

    def candidate_base
      ActionCandidate
        .includes(:business)
        .where(
          "department = :department OR metadata ->> 'candidate_kind' = :kind OR (generation_source = :source AND action_type IN (:action_types))",
          department: "new_business",
          kind: "new_business",
          source: "integrated_decision",
          action_types: NEW_BUSINESS_ACTION_TYPES
        )
    end

    def row_for(candidate, rank)
      metadata = candidate.metadata.to_h
      Row.new(
        rank:,
        action_candidate: candidate,
        business: candidate.business,
        title: candidate.title,
        problem: metadata["problem"].presence || candidate.description.presence || "解決課題は候補詳細で確認してください。",
        target_customer: metadata["target_customer"].presence || metadata["target_user"].presence || "SERP検索意図に近いユーザー",
        revenue_model: metadata["revenue_model"].presence || "LP検証後に価格・課金導線を決めます",
        expected_profit_yen: candidate.expected_profit_yen.to_i,
        expected_hourly_value_yen: candidate.expected_hourly_value_yen.to_i,
        initial_cost_yen: candidate.cost_yen.to_i,
        expected_hours: candidate.expected_hours.to_d,
        validation_step: metadata["validation_step"].presence || "7日以内にLPを公開し、CTAクリック/CV/検索流入を見る",
        source_query: metadata["source_query"].presence || metadata["serp_keyword"].presence || "-",
        market_memo: metadata["market_memo"].presence || candidate.evaluation_reason.presence || "-",
        reason: metadata["recommendation_reason"].presence || candidate.evaluation_reason.presence || "SERP市場観測と内部データの総合判断",
        status: candidate.status
      )
    end

    def zero_reasons
      reasons = []
      latest_serp_run = SerpRun.recent.first
      latest_success_count = latest_serp_run&.serp_analyses&.successful&.count.to_i
      integrated_count = ActionCandidate.where(generation_source: "integrated_decision").count
      inactive_count = candidate_base.count - candidate_base.active_for_ranking.count

      reasons << "SERP Runがまだ実行されていません。" unless latest_serp_run
      reasons << "SERP結果は取得済みですが、成功したSERP分析がありません。" if latest_serp_run && latest_success_count.zero?
      reasons << "SERP結果は取得済みですが、新規事業判定ロジックがActionCandidate化した候補はまだありません。" if latest_success_count.positive? && integrated_count.zero?
      reasons << "候補はありますが、すべて却下・完了・アーカイブ済みです。" if inactive_count.positive? && candidate_base.active_for_ranking.none?
      reasons << "SERP検索クエリが既存事業改善寄りで、新規事業候補の条件を満たしていません。" if reasons.empty?
      reasons
    end
  end
end
