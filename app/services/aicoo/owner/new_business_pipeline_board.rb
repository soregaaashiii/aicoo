module Aicoo
  module Owner
    class NewBusinessPipelineBoard
      Row = Data.define(
        :key,
        :action_candidate,
        :business,
        :title,
        :target_customer,
        :problem,
        :revenue_model,
        :lp_idea,
        :validation_method,
        :serp_evidence,
        :competitors,
        :expected_profit_yen,
        :expected_hourly_value_yen,
        :initial_cost_yen,
        :expected_hours,
        :current_state,
        :next_action_label,
        :next_action_path,
        :next_action_method,
        :next_action_reason,
        :success_condition,
        :rejection_condition,
        :updated_at
      )
      Summary = Data.define(
        :serp_count,
        :integrated_decision_count,
        :pending_count,
        :business_created_count,
        :lp_waiting_count,
        :lp_published_count,
        :validating_count,
        :result_waiting_count,
        :withdrawal_candidate_count
      )
      Result = Data.define(:summary, :rows, :selected, :next_action, :zero_reasons)

      NEW_BUSINESS_ACTION_TYPES = Aicoo::NewBusinessCandidateBoard::NEW_BUSINESS_ACTION_TYPES

      def initialize(selected_id: nil, limit: 30)
        @selected_id = selected_id.to_i if selected_id.present?
        @limit = limit
      end

      def call
        rows = candidate_scope.limit(limit).map { |candidate| row_for(candidate) }
        selected = rows.find { |row| row.action_candidate.id == selected_id } || rows.first

        Result.new(
          summary: summary_for(rows),
          rows:,
          selected:,
          next_action: selected,
          zero_reasons: rows.empty? ? Aicoo::NewBusinessCandidateBoard.call(limit: 1).zero_reasons : []
        )
      end

      private

      attr_reader :selected_id, :limit

      def candidate_scope
        ActionCandidate
          .includes(:business)
          .where(
            "department = :department OR metadata ->> 'candidate_kind' = :kind OR action_type IN (:action_types) OR generation_source IN (:sources)",
            department: "new_business",
            kind: "new_business",
            action_types: NEW_BUSINESS_ACTION_TYPES,
            sources: %w[serp integrated_decision ai_business ai_cross_business]
          )
          .where.not(status: %w[archived done])
          .order(Arel.sql("final_score DESC NULLS LAST, expected_hourly_value_yen DESC NULLS LAST, expected_profit_yen DESC NULLS LAST, updated_at DESC"))
      end

      def row_for(candidate)
        metadata = candidate.metadata.to_h
        business = business_for(candidate)
        Row.new(
          key: "action_candidate:#{candidate.id}",
          action_candidate: candidate,
          business:,
          title: metadata["business_name"].presence || metadata["service_name"].presence || candidate.title,
          target_customer: metadata["target_customer"].presence || metadata["target_user"].presence || "SERP検索意図に近いユーザー",
          problem: metadata["problem"].presence || candidate.description.presence || "候補詳細で解決課題を確認してください。",
          revenue_model: metadata["revenue_model"].presence || "LP検証後に価格・課金導線を決める",
          lp_idea: metadata["lp_idea"].presence || metadata["landing_page_idea"].presence || "課題訴求、CTA、事前登録フォームを持つ検証LP",
          validation_method: metadata["validation_method"].presence || metadata["validation_step"].presence || "7日以内にLPを公開し、PV/CTR/CVを見る",
          serp_evidence: metadata["source_query"].presence || metadata["serp_keyword"].presence || metadata["market_memo"].presence || "-",
          competitors: Array(metadata["competitors"]).presence || Array(metadata["serp_competitors"]).presence || [],
          expected_profit_yen: candidate.expected_profit_yen.to_i,
          expected_hourly_value_yen: candidate.expected_hourly_value_yen.to_i,
          initial_cost_yen: candidate.cost_yen.to_i,
          expected_hours: candidate.expected_hours.to_d,
          current_state: state_for(candidate, business),
          next_action_label: next_action_for(candidate, business)[:label],
          next_action_path: next_action_for(candidate, business)[:path],
          next_action_method: next_action_for(candidate, business)[:method],
          next_action_reason: next_action_for(candidate, business)[:reason],
          success_condition: metadata["success_condition"].presence || "7日以内にCTAクリックまたはCVが発生する",
          rejection_condition: metadata["rejection_condition"].presence || "30日で検索流入・CTAクリック・CVがすべて弱い",
          updated_at: candidate.updated_at
        )
      end

      def business_for(candidate)
        metadata_business_id = candidate.metadata.to_h.dig("business_promotion", "business_id")
        Business.find_by(id: metadata_business_id) || candidate.business
      end

      def state_for(candidate, business)
        return "却下済み" if candidate.status == "rejected"
        return "Business化済み" if candidate.status == "approved" && business.present? && business.id != candidate.business_id
        return "Business化済み" if candidate.metadata.to_h.dig("business_promotion", "promoted")
        return "承認待ち" if candidate.status.in?(%w[idea pending])
        return "LP作成待ち" if candidate.status == "approved"

        candidate.status.presence || "承認待ち"
      end

      def next_action_for(candidate, business)
        routes = Rails.application.routes.url_helpers
        if candidate.status.in?(%w[idea pending])
          return action(
            "Business化する",
            routes.approve_owner_new_business_pipeline_candidate_path(candidate),
            :patch,
            "承認するとBusinessを作成し、事業一覧に反映します。"
          )
        end

        if candidate.status == "rejected"
          return action("却下済み", nil, nil, "この候補は却下済みです。")
        end

        if business
          return action("Businessを見る", routes.business_path(business), :get, "作成済みBusinessでLP/検証を進めます。")
        end

        action("状態を確認", routes.action_candidate_path(candidate), :get, "候補詳細で不足情報を確認します。")
      end

      def action(label, path, method, reason)
        { label:, path:, method:, reason: }
      end

      def summary_for(rows)
        Summary.new(
          serp_count: rows.count { |row| row.action_candidate.generation_source == "serp" },
          integrated_decision_count: rows.count { |row| row.action_candidate.generation_source == "integrated_decision" },
          pending_count: rows.count { |row| row.current_state == "承認待ち" },
          business_created_count: rows.count { |row| row.current_state == "Business化済み" },
          lp_waiting_count: rows.count { |row| row.current_state == "LP作成待ち" },
          lp_published_count: rows.count { |row| row.business&.aicoo_lab_landing_pages&.publicly_available&.exists? },
          validating_count: rows.count { |row| row.business&.lifecycle_stage == "lp_validation" },
          result_waiting_count: rows.count { |row| row.current_state.in?(%w[検証中 結果待ち]) },
          withdrawal_candidate_count: rows.count { |row| row.action_candidate.action_type == "withdraw" }
        )
      end
    end
  end
end
