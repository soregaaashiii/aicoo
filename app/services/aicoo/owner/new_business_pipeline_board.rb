module Aicoo
  module Owner
    class NewBusinessPipelineBoard
      Row = Data.define(
        :key,
        :action_candidate,
        :business,
        :landing_page,
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
        :progress_percent,
        :progress_label,
        :stuck_reason,
        :bucket,
        :next_action_label,
        :next_action_path,
        :next_action_method,
        :next_action_reason,
        :success_condition,
        :rejection_condition,
        :public_lp_path,
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
        landing_page = landing_page_for(business)
        Row.new(
          key: "action_candidate:#{candidate.id}",
          action_candidate: candidate,
          business:,
          landing_page:,
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
          current_state: state_for(candidate, business, landing_page),
          progress_percent: progress_for(candidate, business, landing_page)[:percent],
          progress_label: progress_for(candidate, business, landing_page)[:label],
          stuck_reason: stuck_reason_for(candidate, business, landing_page),
          bucket: bucket_for(candidate, business, landing_page),
          next_action_label: next_action_for(candidate, business, landing_page)[:label],
          next_action_path: next_action_for(candidate, business, landing_page)[:path],
          next_action_method: next_action_for(candidate, business, landing_page)[:method],
          next_action_reason: next_action_for(candidate, business, landing_page)[:reason],
          success_condition: metadata["success_condition"].presence || "7日以内にCTAクリックまたはCVが発生する",
          rejection_condition: metadata["rejection_condition"].presence || "30日で検索流入・CTAクリック・CVがすべて弱い",
          public_lp_path: landing_page&.published_slug.present? ? Rails.application.routes.url_helpers.public_lp_path(landing_page.published_slug) : nil,
          updated_at: candidate.updated_at
        )
      end

      def business_for(candidate)
        promotion = candidate.metadata.to_h["business_promotion"].to_h
        metadata_business = Business.find_by(id: promotion["business_id"])
        return metadata_business if promotion["promoted"] && metadata_business
        return candidate.business if candidate.status == "approved" && promotion["promoted"]

        nil
      end

      def landing_page_for(business)
        business&.aicoo_lab_landing_pages&.order(updated_at: :desc)&.first
      end

      def state_for(candidate, business, landing_page)
        return "却下済み" if candidate.status == "rejected"
        return "候補" if candidate.status.in?(%w[idea pending]) && business.blank?
        return "Business未作成" if candidate.status == "approved" && business.blank?
        return "LP未作成" if business.present? && landing_page.blank?
        return "LP未公開" if landing_page && !landing_page.publicly_visible?
        return "検証中" if landing_page&.publicly_visible?
        return "Business化済み" if candidate.status == "approved" && business.present?
        return "Business化済み" if candidate.metadata.to_h.dig("business_promotion", "promoted")
        return "候補" if candidate.status.in?(%w[idea pending])

        candidate.status.presence || "候補"
      end

      def next_action_for(candidate, business, landing_page)
        routes = Rails.application.routes.url_helpers
        state = state_for(candidate, business, landing_page)
        if state.in?(%w[候補 Business未作成])
          return action(
            "Business作成",
            routes.approve_owner_new_business_pipeline_candidate_path(candidate),
            :patch,
            "1クリックでBusinessを作成し、事業一覧に反映します。"
          )
        end

        if candidate.status == "rejected"
          return action("却下済み", nil, nil, "この候補は却下済みです。")
        end

        if state == "LP未作成"
          return action(
            "LP作成",
            routes.create_lp_owner_new_business_pipeline_candidate_path(candidate),
            :post,
            "作成済みBusinessに検証LPを追加します。"
          )
        end

        if state == "LP未公開"
          return action(
            "LP公開",
            routes.publish_owner_new_business_pipeline_landing_page_path(landing_page),
            :patch,
            "公開LPとして計測開始できる状態にします。"
          )
        end

        if state == "検証中"
          return action("検証結果待ち", nil, nil, "7日/14日/30日のPV・CTR・CVをこのページで確認します。")
        end

        action("状態を確認", nil, nil, "このカード内で不足情報を確認してください。")
      end

      def progress_for(candidate, business, landing_page)
        case state_for(candidate, business, landing_page)
        when "候補" then { percent: 10, label: "Candidate" }
        when "Business未作成" then { percent: 20, label: "Business" }
        when "LP未作成" then { percent: 35, label: "Business" }
        when "LP未公開" then { percent: 55, label: "LP" }
        when "検証中" then { percent: 75, label: "Validation" }
        when "却下済み" then { percent: 0, label: "Rejected" }
        else { percent: 30, label: "Pipeline" }
        end
      end

      def stuck_reason_for(candidate, business, landing_page)
        case state_for(candidate, business, landing_page)
        when "候補" then "Business作成待ち"
        when "Business未作成" then "Business作成が未完了"
        when "LP未作成" then "LP未作成"
        when "LP未公開" then "LP未公開"
        when "検証中" then "計測待ち"
        when "却下済み" then "却下済み"
        else "状態確認が必要"
        end
      end

      def bucket_for(candidate, business, landing_page)
        return :failed if candidate.status == "rejected"
        return :active unless landing_page&.publicly_visible?

        :active
      end

      def action(label, path, method, reason)
        { label:, path:, method:, reason: }
      end

      def summary_for(rows)
        Summary.new(
          serp_count: rows.count { |row| row.action_candidate.generation_source == "serp" },
          integrated_decision_count: rows.count { |row| row.action_candidate.generation_source == "integrated_decision" },
          pending_count: rows.count { |row| row.current_state == "候補" },
          business_created_count: rows.count { |row| row.business.present? },
          lp_waiting_count: rows.count { |row| row.current_state == "LP未作成" },
          lp_published_count: rows.count { |row| row.landing_page&.publicly_visible? },
          validating_count: rows.count { |row| row.current_state == "検証中" },
          result_waiting_count: rows.count { |row| row.current_state.in?(%w[検証中 結果待ち]) },
          withdrawal_candidate_count: rows.count { |row| row.action_candidate.action_type == "withdraw" }
        )
      end
    end
  end
end
