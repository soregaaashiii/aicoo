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
        created = detected_issues.filter_map { |issue| create_candidate(issue) }
        duplicate_count = detected_issues.size - created.size
        duplicate_count.times { skipped << "直近7日以内に同じAnalyzer課題があるため作成しませんでした" }

        Result.new(
          business:,
          analyzer: self.class.name,
          created:,
          skipped:,
          issues: detected_issues,
          handled: true
        )
      end

      private

      attr_reader :business, :today, :skipped

      def handled_business_type?
        false
      end

      def issues
        []
      end

      def create_candidate(issue)
        unless evidence_present?(issue)
          skipped << "#{issue.key}: evidence_missing"
          return
        end
        unless seo_action_type_present?(issue)
          skipped << "#{issue.key}: seo_action_type_missing"
          return
        end

        if recent_duplicate?(issue)
          skipped << "#{issue.key}: duplicate"
          return
        end

        candidate = business.action_candidates.create!(
          title: issue.title,
          description: issue.description,
          action_type: issue.action_type,
          immediate_value_yen: issue.expected_value_yen,
          success_probability: issue.success_probability,
          strategic_value_score: issue.strategic_value_score,
          risk_reduction_score: issue.risk_reduction_score,
          confidence_score: issue.confidence_score,
          data_confidence_score: issue.confidence_score,
          expected_hours: issue.expected_hours,
          cost_yen: 0,
          status: "idea",
          generation_source: "business_analyzer",
          metadata: candidate_metadata(issue),
          evaluation_reason: evaluation_reason(issue),
          execution_prompt: execution_prompt(issue)
        )
        Aicoo::ActionCandidateInstructionStabilizer.call(candidate)
        candidate.reload.update_columns(
          metadata: candidate.metadata.to_h.merge(
            "evidence" => evidence_for(issue),
            "execution_units" => execution_units_for(issue),
            "execution_mode" => execution_mode_for(issue)
          ),
          updated_at: Time.current
        )
        candidate.reload
      end

      def candidate_metadata(issue)
        issue.metadata.to_h.deep_stringify_keys.merge(
          "source" => "business_analyzer",
          "analyzer" => self.class.name,
          "business_type" => business.business_type,
          "issue_key" => issue.key,
          "issue_quantity" => issue.quantity,
          "issue_unit" => issue.unit,
          "issue_why" => issue.why,
          "expected_effect" => issue.expected_effect,
          "analyzer_evidence" => evidence_for(issue),
          "execution_units" => execution_units_for(issue),
          "execution_mode" => execution_mode_for(issue),
          "expected_minutes" => (issue.expected_hours.to_d * 60).round,
          "business_type_playbook" => business.business_type_playbook.call(
            title: issue.title,
            description: issue.description,
            action_type: issue.action_type,
            evaluation_reason: issue.why,
            execution_prompt: issue.expected_effect
          ).metadata
        )
      end

      def evaluation_reason(issue)
        [
          "business_analyzer:#{issue.key}",
          "何を: #{issue.title}",
          "どれだけ: #{issue.quantity}#{issue.unit}",
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
        action_type = attrs["seo_action_type"].to_s
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
        else
          []
        end
      end

      def execution_mode_for(issue)
        action_type = issue.metadata.to_h.deep_stringify_keys["seo_action_type"].to_s
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
          "respond_to_serp_gap" => "content_creation"
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

        issue.metadata.to_h.deep_stringify_keys["seo_action_type"].present?
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
            reason: "喫煙情報の信頼性を上げ、店舗詳細CVRと地図クリックを改善するため"
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

      def genres_for(attrs)
        Array(attrs["target_genres"]).presence || %w[居酒屋 バー カフェ レストラン]
      end

      def unit_hash(attributes)
        attributes.compact.transform_keys(&:to_s)
      end

      def execution_prompt(issue)
        <<~PROMPT.strip
          Analyzerが検出した課題に対して、実行方法だけを具体化してください。

          何を:
          #{issue.title}

          どれだけ:
          #{issue.quantity}#{issue.unit}

          なぜ:
          #{issue.why}

          期待効果:
          #{issue.expected_effect}

          注意:
          課題の再発見や一般論の提案はしないでください。上記の課題を実行する手順、変更対象、完成条件だけを書いてください。
        PROMPT
      end

      def recent_duplicate?(issue)
        business.action_candidates
                .where(created_at: duplicate_window_start..)
                .where(
                  "title = ? OR evaluation_reason LIKE ?",
                  issue.title,
                  "%business_analyzer:#{ActiveRecord::Base.sanitize_sql_like(issue.key)}%"
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
          handled:
        )
      end

      def yen(value)
        value.to_i
      end
    end
  end
end
