module Aicoo
  module OpportunityEngine
    class ActionCandidateConverter
      def initialize(opportunity, analyzer:)
        @opportunity = opportunity
        @analyzer = analyzer
      end

      def call
        business = opportunity.business
        issue = opportunity.source_issue
        decision = Aicoo::UniversalImprovementStrategyEngine.call(opportunity)
        return unless decision.valid?

        plan = Aicoo::ActionPlanner.call(opportunity, analyzer:, decision:)
        return unless plan.valid?

        concretization_warnings = concretization_warnings_for(plan)
        concretization_status = concretization_warnings.empty? ? "ready" : "needs_refinement"

        metadata = sanitize_metadata(analyzer.candidate_metadata(issue, opportunity:).merge(
          "action_plan" => plan.to_metadata,
          "decision" => decision.to_metadata,
          "strategy_engine" => "Aicoo::UniversalImprovementStrategyEngine",
          "strategy_ranking" => decision.to_metadata["strategy_ranking"],
          "business_knowledge" => decision.business_knowledge.to_h,
          "concrete_task" => decision.concrete_task,
          "target" => decision.target,
          "target_type" => decision.target_type,
          "target_url_or_identifier" => decision.target_url_or_identifier,
          "execution_mode" => decision.execution_mode,
          "work_type" => work_type_for(issue, decision),
          "article_candidate" => article_candidate_metadata_for(issue, decision),
          "search_query" => article_candidate_metadata_for(issue, decision)&.fetch("search_query", nil),
          "search_intent" => article_candidate_metadata_for(issue, decision)&.fetch("search_intent", nil),
          "recommended_title" => article_candidate_metadata_for(issue, decision)&.fetch("recommended_title", nil),
          "recommended_url_slug" => article_candidate_metadata_for(issue, decision)&.fetch("recommended_url_slug", nil),
          "article_summary" => article_candidate_metadata_for(issue, decision)&.fetch("article_summary", nil),
          "article_reason" => article_candidate_metadata_for(issue, decision)&.fetch("article_reason", nil),
          "expected_pv" => article_candidate_metadata_for(issue, decision)&.fetch("expected_pv", nil),
          "expected_ctr_lift" => article_candidate_metadata_for(issue, decision)&.fetch("expected_ctr_lift", nil),
          "required_data" => article_candidate_metadata_for(issue, decision)&.fetch("required_data", nil),
          "execution_units" => decision.execution_units,
          "concretization_status" => concretization_status,
          "concretization_warnings" => concretization_warnings,
          "codex_eligible" => decision.execution_mode == "code_revision"
        ))

        candidate = business.action_candidates.create!(
          title: plan.summary,
          description: plan.goal,
          action_type: action_type_for(issue, decision),
          immediate_value_yen: decision.expected_profit_yen,
          success_probability: decision.success_probability,
          strategic_value_score: issue.strategic_value_score,
          risk_reduction_score: issue.risk_reduction_score,
          confidence_score: opportunity.confidence,
          data_confidence_score: opportunity.confidence,
          expected_hours: decision.expected_hours,
          cost_yen: decision.cost_yen,
          status: status_for(issue, decision),
          generation_source: "business_analyzer",
          metadata:,
          evaluation_reason: evaluation_reason_for(plan),
          execution_prompt: execution_prompt_for(plan)
        )
        Aicoo::ActionCandidateInstructionStabilizer.call(candidate)
        candidate.reload.update_columns(
          metadata: sanitize_metadata(candidate.metadata.to_h.merge(
            "action_plan" => plan.to_metadata,
            "decision" => decision.to_metadata,
            "strategy_engine" => "Aicoo::UniversalImprovementStrategyEngine",
            "strategy_ranking" => decision.to_metadata["strategy_ranking"],
            "business_knowledge" => decision.business_knowledge.to_h,
            "opportunity" => opportunity.to_metadata,
            "evidence" => analyzer.evidence_for(issue),
            "data_sources_used" => data_sources_used_for(issue),
            "execution_units" => plan.execution_units,
            "execution_mode" => plan.execution_mode,
            "work_type" => work_type_for(issue, decision),
            "article_candidate" => article_candidate_metadata_for(issue, decision),
            "concrete_task" => plan.summary,
            "concretization_status" => concretization_status,
            "concretization_warnings" => concretization_warnings,
            "codex_eligible" => plan.execution_mode == "code_revision"
          )),
          execution_prompt: execution_prompt_for(plan),
          updated_at: Time.current
        )
        candidate.reload
      end

      private

      attr_reader :opportunity, :analyzer

      def sanitize_metadata(metadata)
        Aicoo::ActionCandidateTargetSanitizer.call(business: opportunity.business, metadata:)
      end

      def action_type_for(issue, decision)
        return "new_article_candidate" if decision.selected&.strategy_type == "new_article_candidate"
        return "opportunity_validation" if decision.selected&.strategy_type == "search_intent_analysis"
        return "data_preparation" if decision.selected&.strategy_type == "data_shortage"

        value = issue.action_type.to_s
        return value if ActionCandidate::ACTION_TYPES.include?(value)

        {
          "lp_improvement" => "ui_improvement",
          "asset_creation" => "build_lp",
          "operations" => "data_preparation"
        }.fetch(value, "other")
      end

      def work_type_for(issue, decision)
        attrs = issue.metadata.to_h.deep_stringify_keys
        attrs["work_type"].presence ||
          attrs["creation_type"].presence ||
          decision.selected&.strategy_type.presence
      end

      def status_for(issue, decision)
        action_type_for(issue, decision) == "new_article_candidate" ? "proposal" : "idea"
      end

      def article_candidate_metadata_for(_issue, decision)
        selected = decision.selected
        return unless selected&.strategy_type == "new_article_candidate"

        selected.required_resources.to_h.deep_stringify_keys["article_candidate"].presence ||
          selected.supporting_metrics.to_h.deep_stringify_keys["article_candidate"].presence
      end

      def evaluation_reason_for(plan)
        [
          "business_analyzer:#{opportunity.key}",
          "opportunity:#{opportunity.key}",
          "action_planner:#{opportunity.key}",
          plan.owner_output
        ].join("\n")
      end

      def execution_prompt_for(plan)
        return nil unless plan.execution_mode == "code_revision"

        <<~PROMPT.strip
          Action Planner 作業指示

          #{plan.owner_output}

          実行手順:
          #{plan.execution_steps.map.with_index(1) { |step, index| "#{index}. #{step}" }.join("\n")}

          完了条件:
          - 上記手順が完了している
          - 実行結果をActionResultへ登録できるメモがある
        PROMPT
      end

      def data_sources_used_for(issue)
        analyzer.evidence_for(issue).fetch("source", []).map(&:to_s).map do |source|
          source == "business_db" ? "internal" : source
        end.uniq
      end

      ABSTRACT_PATTERNS = [
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
        /記事を増やす/,
        /Analyzer/i
      ].freeze

      def concretization_warnings_for(plan)
        warnings = []
        text = plan.summary.to_s.strip
        warnings << "concrete_task_missing" if text.blank?
        warnings << "concrete_task_abstract" if ABSTRACT_PATTERNS.any? { |pattern| text.match?(pattern) }
        warnings << "target_unspecified" if plan.target.to_s.blank? || plan.target.to_s.include?("未特定")
        warnings << "execution_units_missing" if plan.execution_units.blank?

        warnings
      end
    end
  end
end
