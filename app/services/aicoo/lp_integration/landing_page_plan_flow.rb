module Aicoo
  module LpIntegration
    class LandingPagePlanFlow
      Result = Data.define(:generation_run, :candidate, :task, :items)

      def initialize(
        business:,
        campaign: nil,
        attributes: {},
        recommendations: nil,
        strategy_builder_class: LandingPageStrategyBuilder
      )
        @business = business
        @campaign = campaign
        @attributes = attributes.to_h.deep_stringify_keys
        @recommendations = recommendations
        @strategy_builder_class = strategy_builder_class
      end

      def call
        planned_items = build_items
        raise ArgumentError, "生成できる不足LPがありません。" if planned_items.empty?

        result = nil
        Business.transaction do
          generation_run = create_generation_run!(planned_items)
          candidate = create_candidate!(generation_run, planned_items)
          task = create_task!(generation_run, candidate, planned_items)
          generation_run.update!(metadata: generation_run.metadata.to_h.merge(
            "action_candidate_id" => candidate.id,
            "auto_revision_task_id" => task.id
          ))
          result = Result.new(generation_run:, candidate:, task:, items: planned_items)
        end
        result
      end

      private

      attr_reader :business, :campaign, :attributes, :recommendations, :strategy_builder_class

      def build_items
        source_rows = recommendations ? Array(recommendations) : [ single_recommendation ]
        source_rows.flat_map do |row|
          values = normalize_utf8(row.to_h.deep_stringify_keys)
          planning_campaign = resolve_planning_campaign(values)
          strategy = normalize_utf8(strategy_builder_class.new(
            business:,
            campaign: planning_campaign,
            purpose: values.fetch("purpose"),
            notes: values["notes"],
            advanced: values.fetch("advanced", {})
          ).call)
          strategy["expected_organic_visits"] = values["expected_organic_visits"].to_i
          strategy["expected_ad_visits"] = values["expected_ad_visits"].to_i
          count = [ values["missing_count"].to_i, 1 ].max
          count.times.map { |index| build_item(values, strategy, index, count) }
        end
      end

      def single_recommendation
        raise ArgumentError, "このBusinessのCampaignではありません。" unless campaign&.business_id == business.id
        purpose = attributes.fetch("purpose").to_s
        raise ArgumentError, "作成目的を選択してください。" unless purpose.in?(LandingPageStrategyBuilder::PURPOSES)

        {
          "campaign_id" => campaign.id,
          "campaign_name" => campaign.name,
          "campaign_type" => campaign.campaign_type,
          "purpose" => purpose,
          "missing_count" => 1,
          "name" => attributes["name"],
          "notes" => attributes["notes"],
          "advanced" => attributes.fetch("advanced", {})
        }
      end

      def resolve_planning_campaign(values)
        existing = business.business_campaigns.active.find_by(id: values["campaign_id"])
        return existing if existing

        BusinessCampaign.new(
          business:,
          name: values["campaign_name"].presence || LandingPageStrategyBuilder::PURPOSES.fetch(values.fetch("purpose")),
          campaign_type: values["campaign_type"].presence || BusinessLandingPagePlanner::PURPOSE_CAMPAIGN_TYPES.fetch(values.fetch("purpose")),
          status: "active",
          metadata: { "planner_purpose" => values.fetch("purpose") }
        )
      end

      def build_item(values, strategy, index, count)
        purpose = values.fetch("purpose")
        keywords = Array(strategy["keywords"]).compact_blank
        primary_keyword = keywords[index % keywords.size] if keywords.any?
        item_strategy = strategy.deep_dup
        item_strategy["primary_keyword"] = primary_keyword if primary_keyword
        item_strategy["portfolio_position"] = index + 1
        item_strategy["portfolio_size"] = count
        {
          "campaign_id" => values["campaign_id"],
          "campaign_name" => values["campaign_name"],
          "campaign_type" => values["campaign_type"],
          "purpose" => purpose,
          "purpose_label" => LandingPageStrategyBuilder::PURPOSES.fetch(purpose),
          "name" => generated_name(values, index, count, primary_keyword),
          "notes" => values["notes"],
          "advanced" => values.fetch("advanced", {}),
          "strategy" => item_strategy
        }.compact
      end

      def generated_name(values, index, count, primary_keyword)
        return values["name"] if values["name"].present? && count == 1

        base = primary_keyword.presence || values["campaign_name"].presence ||
          LandingPageStrategyBuilder::PURPOSES.fetch(values.fetch("purpose"))
        count == 1 ? "#{base} LP" : "#{base} LP#{index + 1}"
      end

      def create_generation_run!(items)
        totals = aggregate(items)
        AicooLabGenerationRun.create!(
          generation_type: "lp_generation",
          status: "draft",
          prompt: plan_summary(items, totals),
          generated_count: 0,
          started_at: Time.current,
          metadata: {
            "pipeline" => "aicoo_lp_planner",
            "pipeline_status" => "waiting_approval",
            "pipeline_stage" => "prompt_pending",
            "pipeline_stages" => LandingPagePipelineState.build(current: "prompt_pending"),
            "business_id" => business.id,
            "business_name" => business.name,
            "plan_type" => recommendations ? "recommended_batch" : "single",
            "plan_items" => items,
            "review_metrics" => totals,
            "ranking_metric" => "expected_profit_yen",
            "manual_approval_required" => true,
            "auto_submit_enabled" => false,
            "auto_deploy_enabled" => false,
            "cloudflare_project_name" => business.metadata.to_h["lp_cloudflare_project_name"],
            "ga4_property_id" => shared_analytics_site&.ga4_property_id,
            "gsc_site_url" => shared_analytics_site&.gsc_site_url,
            "created_by" => "aicoo_lp_planner",
            "created_at" => Time.current.iso8601
          }.compact
        )
      end

      def create_candidate!(generation_run, items)
        totals = generation_run.metadata.to_h.fetch("review_metrics")
        business.action_candidates.create!(
          title: "#{items.size}件のLP生成計画を確認する",
          description: "AICOOが不足LPと制作戦略を生成しました。レビューで承認された場合だけLPごとのLovable Promptを作成します。",
          evaluation_reason: "期待利益#{totals.fetch('expected_profit_yen')}円のLP計画を、Owner承認前で停止しています。",
          action_type: "build_lp",
          generation_source: "ai_business",
          department: "revenue",
          status: "proposal",
          immediate_value_yen: totals.fetch("expected_profit_yen").to_i,
          expected_hours: totals.fetch("estimated_work_hours").to_d,
          success_probability: average_confidence(items),
          confidence_score: (average_confidence(items) * 100).round,
          data_confidence_score: (average_confidence(items) * 100).round,
          execution_prompt: generation_run.prompt,
          metadata: {
            "workflow_type" => "lp_generation_plan",
            "execution_mode" => "lp_plan_approval",
            "source_system" => "aicoo_lp_planner",
            "generation_run_id" => generation_run.id,
            "lp_count" => items.size,
            "expected_profit_yen" => totals.fetch("expected_profit_yen"),
            "ranking_metric" => "expected_profit_yen",
            "owner_approval_required" => true,
            "auto_revision" => false,
            "auto_merge" => false,
            "auto_deploy" => false
          }
        )
      end

      def create_task!(generation_run, candidate, items)
        totals = generation_run.metadata.to_h.fetch("review_metrics")
        AutoRevisionTask.create!(
          action_candidate: candidate,
          business:,
          target_business: business,
          target_repository_name: "lp-generation-plan-#{generation_run.id}",
          target_repository_type: "planning",
          title: candidate.title,
          execution_prompt: generation_run.prompt,
          priority_score: totals.fetch("expected_profit_yen").to_i,
          generated_by: "aicoo_lp_planner",
          risk_level: "medium",
          status: "waiting_approval",
          metadata: {
            "workflow_type" => "lp_generation_plan",
            "generation_run_id" => generation_run.id,
            "pipeline_stage" => "prompt_pending",
            "pipeline_stages" => LandingPagePipelineState.build(current: "prompt_pending"),
            "lp_count" => items.size,
            "manual_approval_required" => true,
            "approval_required_reason" => "LP生成数、期待利益、利用量を確認してからPrompt生成へ進めます。",
            "auto_submit_enabled" => false,
            "auto_merge_enabled" => false,
            "auto_deploy_enabled" => false,
            "service_repository_protected" => true,
            "expected_profit_yen" => totals.fetch("expected_profit_yen")
          }
        )
      end

      def aggregate(items)
        {
          "lp_count" => items.size,
          "purposes" => items.map { |item| item.fetch("purpose_label") }.tally,
          "expected_profit_yen" => items.sum { |item| item.dig("strategy", "expected_profit_yen").to_i },
          "expected_cv" => items.sum { |item| item.dig("strategy", "expected_cv").to_f }.round(2),
          "expected_hourly_value_yen" => aggregate_hourly_value(items),
          "expected_organic_visits" => items.sum { |item| item.dig("strategy", "expected_organic_visits").to_i },
          "expected_ad_visits" => items.sum { |item| item.dig("strategy", "expected_ad_visits").to_i },
          "estimated_work_hours" => items.sum { |item| item.dig("strategy", "estimated_work_hours").to_f }.round(2),
          "codex_usage_count" => items.size,
          "lovable_usage_count" => items.size,
          "cloudflare_publish_count" => items.size
        }
      end

      def aggregate_hourly_value(items)
        profit = items.sum { |item| item.dig("strategy", "expected_profit_yen").to_i }
        hours = items.sum { |item| item.dig("strategy", "estimated_work_hours").to_f }
        hours.positive? ? (profit / hours).round : 0
      end

      def average_confidence(items)
        values = items.map { |item| item.dig("strategy", "confidence").to_d }
        return 0.to_d if values.empty?

        values.sum / values.size
      end

      def plan_summary(items, totals)
        rows = items.map.with_index do |item, index|
          "#{index + 1}. #{item.fetch('name')} / #{item.fetch('purpose_label')} / 期待利益 #{item.dig('strategy', 'expected_profit_yen').to_i}円"
        end
        <<~TEXT
          #{business.name} LP生成計画

          #{rows.join("\n")}

          合計LP数: #{totals.fetch('lp_count')}
          合計期待利益: #{totals.fetch('expected_profit_yen')}円
          推定制作時間: #{totals.fetch('estimated_work_hours')}時間
          Ownerが実行を承認するまでLovable、GitHub、Cloudflareへ送信しません。
        TEXT
      end

      def normalize_utf8(value)
        case value
        when Hash
          value.to_h { |key, child| [ normalize_utf8(key), normalize_utf8(child) ] }
        when Array
          value.map { |child| normalize_utf8(child) }
        when String
          text = value.dup
          text.force_encoding(Encoding::UTF_8) if text.encoding == Encoding::ASCII_8BIT
          text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
        else
          value
        end
      end

      def shared_analytics_site
        @shared_analytics_site ||= AicooAnalyticsSite.where(business:).recent.first
      end
    end
  end
end
