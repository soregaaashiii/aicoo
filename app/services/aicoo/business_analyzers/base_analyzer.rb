module Aicoo
  module BusinessAnalyzers
    class BaseAnalyzer
      Issue = Data.define(
        :key,
        :title,
        :description,
        :action_type,
        :quantity,
        :unit,
        :why,
        :expected_effect,
        :expected_value_yen,
        :success_probability,
        :strategic_value_score,
        :risk_reduction_score,
        :expected_hours,
        :confidence_score,
        :metadata
      )

      def self.call(...)
        new(...).call
      end

      def initialize(business:, today: Date.current)
        @business = business
        @today = today.to_date
        @skipped = []
      end

      def call
        return empty_result(handled: false) unless handled_business_type?

        detected_issues = issues.compact
        opportunities = detected_issues.filter_map { |issue| opportunity_from_issue(issue) }
        created = opportunities.filter_map { |opportunity| create_candidate(opportunity) }
        duplicate_count = opportunities.size - created.size
        duplicate_count.times { skipped << "直近7日以内に同じAnalyzer課題があるため作成しませんでした" }

        Result.new(
          business:,
          analyzer: self.class.name,
          created:,
          skipped:,
          issues: detected_issues,
          opportunities:,
          handled: true
        )
      end

      attr_reader :business, :today, :skipped

      def opportunity_from_issue(issue)
        unless evidence_present?(issue)
          skipped << "#{issue.key}: evidence_missing"
          return
        end
        unless seo_action_type_present?(issue)
          skipped << "#{issue.key}: seo_action_type_missing"
          return
        end

        metrics = supporting_metrics_for(issue)
        Aicoo::OpportunityEngine::Opportunity.new(
          key: issue.key,
          business:,
          source_analyzer: self.class.name,
          opportunity_type: opportunity_type_for(issue),
          target: opportunity_target_for(issue, metrics),
          reason: issue.why,
          expected_value_yen: issue.expected_value_yen,
          expected_hours: issue.expected_hours,
          success_probability: issue.success_probability,
          confidence: issue.confidence_score,
          execution_mode: execution_mode_for(issue),
          required_resources: required_resources_for(issue),
          supporting_metrics: metrics,
          source_issue: issue
        )
      end

      def create_candidate(opportunity)
        issue = opportunity.source_issue
        if recent_duplicate?(issue)
          skipped << "#{issue.key}: duplicate"
          return
        end

        Aicoo::OpportunityEngine::ActionCandidateConverter.new(opportunity, analyzer: self).call
      end

      def candidate_metadata(issue, opportunity: nil)
        issue.metadata.to_h.deep_stringify_keys.merge(
          "source" => "business_analyzer",
          "analyzer" => self.class.name,
          "business_type" => business.business_type,
          "issue_key" => issue.key,
          "issue_quantity" => issue.quantity,
          "issue_unit" => issue.unit,
          "issue_why" => issue.why,
          "opportunity" => opportunity&.to_metadata,
          "opportunity_type" => opportunity&.opportunity_type || opportunity_type_for(issue),
          "action_title" => issue.title,
          "target" => opportunity&.target || opportunity_target_for(issue, supporting_metrics_for(issue)),
          "target_type" => issue.metadata.to_h.deep_stringify_keys["target_type"].presence,
          "target_url_or_identifier" => issue.metadata.to_h.deep_stringify_keys["target_url_or_identifier"].presence ||
            issue.metadata.to_h.deep_stringify_keys["target_identifier"].presence,
          "concrete_task" => issue.metadata.to_h.deep_stringify_keys["concrete_task"].presence || issue.title,
          "target_amount" => issue.quantity,
          "supporting_metrics" => opportunity&.supporting_metrics || supporting_metrics_for(issue),
          "codex_eligible" => (opportunity&.execution_mode || execution_mode_for(issue)) == "code_revision",
          "expected_effect" => issue.expected_effect,
          "analyzer_evidence" => evidence_for(issue),
          "execution_units" => execution_units_for(issue),
          "execution_mode" => opportunity&.execution_mode || execution_mode_for(issue),
          "expected_minutes" => (issue.expected_hours.to_d * 60).round,
          "business_type_playbook" => business.business_type_playbook.call(
            title: issue.title,
            description: issue.description,
            action_type: issue.action_type,
            evaluation_reason: issue.why,
            execution_prompt: issue.expected_effect
          ).metadata
        ).compact
      end

      def evaluation_reason(issue, opportunity: nil)
        [
          "business_analyzer:#{issue.key}",
          "opportunity:#{opportunity&.key || issue.key}",
          "次にやること: #{issue.title}",
          "対象: #{opportunity&.target.to_h['label'].presence || issue.title}",
          "実施量: #{issue.quantity}#{issue.unit}",
          "なぜ: #{issue.why}",
          "期待効果: #{issue.expected_effect}"
        ].join("\n")
      end

      def evidence_for(issue)
        attrs = issue.metadata.to_h.deep_stringify_keys
        {
          "source" => Array(attrs["evidence_sources"].presence || attrs["data_sources"].presence || attrs["source"].presence || "business_db"),
          "issue_type" => issue.key,
          "query" => attrs["source_query"].presence,
          "page_path" => attrs["page_path"].presence || Array(attrs["candidate_pages"]).find { |path| path.to_s.start_with?("/") },
          "area" => attrs["target_area"].presence,
          "genre" => attrs["target_genre"].presence,
          "current_value" => attrs["current_value"].presence,
          "benchmark_value" => attrs["benchmark_value"].presence,
          "metric_before" => attrs["metric_before"].presence || attrs["current_value"].presence,
          "target_amount" => issue.quantity,
          "target_unit" => issue.unit,
          "reason" => issue.why,
          "expected_effect" => issue.expected_effect
        }.compact
      end

      def execution_units_for(issue)
        attrs = issue.metadata.to_h.deep_stringify_keys
        action_type = attrs["seo_action_type"].presence || attrs["opportunity_type"].to_s
        case action_type
        when "add_listings"
          listing_units(issue, attrs)
        when "verify_listings"
          verification_units(issue, attrs)
        when "create_area_article", "create_genre_article"
          article_units(issue, attrs)
        when "add_shop_links", "improve_cv_path"
          shop_link_units(issue, attrs)
        when "improve_ctr_title"
          ctr_title_units(issue, attrs)
        when "respond_to_serp_gap"
          serp_gap_units(issue, attrs)
        when "demand_without_asset"
          demand_without_asset_units(issue, attrs)
        when "high_impression_low_ctr"
          ctr_title_units(issue, attrs)
        when "rank_11_20_gap"
          serp_gap_units(issue, attrs)
        when "traffic_without_conversion"
          conversion_path_units(issue, attrs)
        when "asset_without_traffic"
          asset_traffic_units(issue, attrs)
        when "activity_gap", "data_quality_gap"
          operation_units(issue, attrs)
        else
          []
        end
      end

      def execution_mode_for(issue)
        action_type = issue.metadata.to_h.deep_stringify_keys.then { |attrs| attrs["seo_action_type"].presence || attrs["opportunity_type"].to_s }
        {
          "add_listings" => "data_operation",
          "verify_listings" => "manual_operation",
          "create_area_article" => "content_creation",
          "create_genre_article" => "content_creation",
          "rewrite_existing_article" => "content_creation",
          "add_shop_links" => "code_revision",
          "improve_shop_page" => "code_revision",
          "improve_cv_path" => "code_revision",
          "improve_ctr_title" => "content_creation",
          "respond_to_serp_gap" => "content_creation",
          "demand_without_asset" => "content_creation",
          "high_impression_low_ctr" => "content_creation",
          "rank_11_20_gap" => "content_creation",
          "traffic_without_conversion" => "code_revision",
          "asset_without_traffic" => "content_creation",
          "activity_gap" => "manual_operation",
          "data_quality_gap" => "code_revision"
        }.fetch(action_type, "code_revision")
      end

      def evidence_present?(issue)
        evidence = evidence_for(issue)
        %w[target_amount query page_path area genre metric_before benchmark_value current_value].any? do |key|
          evidence[key].present?
        end
      end

      def seo_action_type_present?(issue)
        return true unless business.business_type.in?(Aicoo::BusinessAnalyzers::SeoBusinessAnalyzer::SEO_MEDIA_TYPES)

        attrs = issue.metadata.to_h.deep_stringify_keys
        attrs["seo_action_type"].present? || attrs["opportunity_type"].present?
      end

      def execution_prompt(issue, opportunity: nil)
        target = opportunity&.target.to_h["label"].presence || issue.title
        <<~PROMPT.strip
          Opportunityに対して、実行方法だけを具体化してください。

          次にやること:
          #{issue.title}

          対象:
          #{target}

          実施量:
          #{issue.quantity}#{issue.unit}

          なぜ:
          #{issue.why}

          期待効果:
          #{issue.expected_effect}

          注意:
          課題の再発見や一般論の提案はしないでください。上記Opportunityを実行する手順、変更対象、完成条件だけを書いてください。
        PROMPT
      end

      private

      def handled_business_type?
        false
      end

      def issues
        []
      end

      def opportunity_type_for(issue)
        attrs = issue.metadata.to_h.deep_stringify_keys
        attrs["opportunity_type"].presence || attrs["seo_action_type"].presence || issue.action_type
      end

      def opportunity_target_for(issue, metrics)
        {
          "label" => [
            metrics["query"].presence && "「#{metrics['query']}」",
            metrics["page_path"],
            metrics["area"].presence && "#{metrics['area']}エリア",
            metrics["genre"]
          ].compact_blank.join(" / ").presence || issue.title,
          "query" => metrics["query"],
          "page_path" => metrics["page_path"],
          "area" => metrics["area"],
          "genre" => metrics["genre"],
          "amount" => issue.quantity,
          "unit" => issue.unit
        }.compact
      end

      def supporting_metrics_for(issue)
        attrs = issue.metadata.to_h.deep_stringify_keys
        evidence_for(issue).merge(
          "source_metric" => attrs["source_metric"],
          "expected_effect" => issue.expected_effect,
          "candidate_pages" => attrs["candidate_pages"],
          "candidate_keywords" => attrs["candidate_keywords"],
          "serp_analysis_id" => attrs["serp_analysis_id"]
        ).compact
      end

      def required_resources_for(issue)
        {
          "execution_units" => execution_units_for(issue),
          "estimated_minutes" => (issue.expected_hours.to_d * 60).round,
          "execution_mode" => execution_mode_for(issue)
        }
      end

      def listing_units(issue, attrs)
        area = attrs["target_area"].presence || attrs["area"].presence || "対象エリア"
        remaining = issue.quantity.to_i
        genres_for(attrs).filter_map do |genre|
          next if remaining <= 0

          amount = [ remaining, 20 ].min
          remaining -= amount
          unit_hash(
            label: "#{area} #{genre}を#{amount}件追加",
            area:,
            genre:,
            target_amount: amount,
            estimated_minutes: amount * 2,
            reason: "#{area}の#{genre}検索需要に対して掲載店舗数が不足しているため"
          )
        end
      end

      def verification_units(issue, attrs)
        area = attrs["target_area"].presence || attrs["area"].presence || "流入上位エリア"
        remaining = issue.quantity.to_i
        pages = Array(attrs["candidate_pages"]).presence || [ area ]
        pages.filter_map do |page|
          next if remaining <= 0

          amount = [ remaining, 25 ].min
          remaining -= amount
          unit_hash(
            label: "#{page}の未確認店舗を#{amount}件確認済みにする",
            area: page.to_s.include?("ページ") ? area : page,
            target_amount: amount,
            estimated_minutes: amount * 1,
            reason: "掲載情報の信頼性を上げ、詳細ページのCVRと主要導線クリックを改善するため"
          )
        end
      end

      def article_units(_issue, attrs)
        keywords = Array(attrs["candidate_keywords"]).presence || [ attrs["source_query"].presence || attrs["recommended_title"].presence ].compact
        keywords.first(3).map do |keyword|
          unit_hash(
            label: "「#{keyword}」の記事を1本作成",
            query: keyword,
            target_amount: 1,
            estimated_minutes: 90,
            reason: "検索需要に対して記事入口が不足しているため"
          )
        end
      end

      def shop_link_units(issue, attrs)
        remaining = issue.quantity.to_i
        pages = Array(attrs["candidate_pages"]).presence || [ attrs["page_path"].presence || "流入上位ページ" ]
        pages.filter_map do |page|
          next if remaining <= 0

          amount = [ remaining, 10 ].min
          remaining -= amount
          unit_hash(
            label: "#{page}に店舗リンクを#{amount}件追加",
            page_path: page,
            target_amount: amount,
            estimated_minutes: amount * 4,
            reason: "流入後の回遊と電話・地図・アフィリエイト導線を増やすため"
          )
        end
      end

      def ctr_title_units(issue, attrs)
        pages = Array(attrs["candidate_pages"]).presence || [ attrs["page_path"].presence || attrs["source_query"].presence || issue.title ]
        pages.first(issue.quantity.to_i.clamp(1, 8)).map.with_index(1) do |page, index|
          unit_hash(
            label: "#{page} のSEOタイトル/metaを1件改善",
            page_path: page.to_s.start_with?("/") ? page : nil,
            query: attrs["source_query"].presence,
            target_amount: 1,
            estimated_minutes: 20,
            reason: "高順位または表示回数があるのにCTRが低いため",
            order: index
          )
        end
      end

      def serp_gap_units(_issue, attrs)
        query = attrs["source_query"].presence || "対象検索クエリ"
        [ unit_hash(
          label: "「#{query}」のSERP差分を1件埋める",
          query:,
          target_amount: 1,
          estimated_minutes: 120,
          reason: "競合上位にあり自サイトに不足している比較表・FAQ・内部リンクを補うため"
        ) ]
      end

      def demand_without_asset_units(issue, attrs)
        target = attrs["target_identifier"].presence || attrs["source_query"].presence || issue.title
        [ unit_hash(
          label: issue.title,
          query: attrs["source_query"].presence,
          target_amount: issue.quantity,
          estimated_minutes: (issue.expected_hours.to_d * 60).round,
          reason: "需要がある一方で対応資産が不足しているため",
          target_type: attrs["target_type"].presence,
          target_identifier: target
        ) ]
      end

      def conversion_path_units(issue, attrs)
        target = attrs["target_identifier"].presence || "流入上位ページ"
        [ unit_hash(
          label: issue.title,
          page_path: target.to_s.start_with?("/") ? target : nil,
          target_amount: issue.quantity,
          estimated_minutes: (issue.expected_hours.to_d * 60).round,
          reason: "流入に対してCVイベントが少ないため",
          target_type: attrs["target_type"].presence,
          target_identifier: target
        ) ]
      end

      def asset_traffic_units(issue, attrs)
        target = attrs["target_identifier"].presence || "作成済み資産"
        [ unit_hash(
          label: issue.title,
          target_amount: issue.quantity,
          estimated_minutes: (issue.expected_hours.to_d * 60).round,
          reason: "作成済み資産に流入がないため",
          target_type: attrs["target_type"].presence,
          target_identifier: target
        ) ]
      end

      def operation_units(issue, attrs)
        target = attrs["target_identifier"].presence || issue.title
        [ unit_hash(
          label: issue.title,
          target_amount: issue.quantity,
          estimated_minutes: (issue.expected_hours.to_d * 60).round,
          reason: issue.why,
          target_type: attrs["target_type"].presence,
          target_identifier: target
        ) ]
      end

      def genres_for(attrs)
        Array(attrs["target_genres"]).presence || %w[居酒屋 バー カフェ レストラン]
      end

      def unit_hash(attributes)
        attributes.compact.transform_keys(&:to_s)
      end

      def recent_duplicate?(issue)
        business.action_candidates
                .where(created_at: duplicate_window_start..)
                .where(
                  "title = ? OR evaluation_reason LIKE ?",
                  issue.title,
                  "%#{ActiveRecord::Base.sanitize_sql_like(issue.key)}%"
                )
                .exists?
      end

      def duplicate_window_start
        today.beginning_of_day - 7.days
      end

      def empty_result(handled:)
        Result.new(
          business:,
          analyzer: self.class.name,
          created: [],
          skipped: [],
          issues: [],
          opportunities: [],
          handled:
        )
      end

      def yen(value)
        value.to_i
      end
    end
  end
end
