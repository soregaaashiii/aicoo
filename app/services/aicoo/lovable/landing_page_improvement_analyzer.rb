require "digest"

module Aicoo
  module Lovable
    class LandingPageImprovementAnalyzer
      GENERATION_SOURCE = "lp_learning".freeze
      PERFORMANCE_GAP_RATIO = 0.30
      MAX_CANDIDATES_PER_VERSION = 3
      ESTIMATED_WORK_HOURS = {
        "cta_improvement" => 0.5,
        "first_view_improvement" => 1.0,
        "structure_improvement" => 1.5,
        "form_improvement" => 1.0,
        "design_improvement" => 1.5,
        "seo_improvement" => 1.0
      }.freeze

      Improvement = Data.define(:type, :title, :reason, :target_metric, :current_value, :benchmark_value, :severity, :change_request)
      Result = Data.define(
        :business,
        :generation_run,
        :learning,
        :comparison,
        :analysis_status,
        :improvements,
        :candidates,
        :duplicate_count,
        :skip_reason
      )

      def initialize(business:, generation_run: nil, persist: true)
        @business = business
        @repository = VersionRepository.new(business:)
        @generation_run = generation_run || @repository.published
        @persist = persist
      end

      def call
        return empty_result("published_version_not_found") unless generation_run

        learning = LearningSummary.new(business:, generation_run:).call(persist: persist)
        comparison = LandingPageLearningComparison.new(
          business:,
          repository:,
          learning_overrides: { generation_run.id => learning }
        ).call
        unless learning["pageviews"].to_i >= LandingPageLearningComparison::MIN_PAGEVIEWS
          persist_analysis!(learning:, comparison:, improvements: [], status: "collecting", skip_reason: "insufficient_pageviews")
          return result(learning:, comparison:, improvements: [], candidates: [], duplicate_count: 0, status: "collecting", skip_reason: "insufficient_pageviews")
        end
        if comparison.benchmark.blank?
          persist_analysis!(learning:, comparison:, improvements: [], status: "collecting", skip_reason: "benchmark_unavailable")
          return result(learning:, comparison:, improvements: [], candidates: [], duplicate_count: 0, status: "collecting", skip_reason: "benchmark_unavailable")
        end

        improvements = detect_improvements(learning, comparison).sort_by { |item| -item.severity }.first(MAX_CANDIDATES_PER_VERSION)
        candidates, duplicate_count = materialize_candidates(improvements, learning, comparison)
        status = improvements.any? ? "improvement_found" : "healthy"
        persist_analysis!(learning:, comparison:, improvements:, status:, skip_reason: nil)
        result(learning:, comparison:, improvements:, candidates:, duplicate_count:, status:, skip_reason: nil)
      end

      private

      attr_reader :business, :repository, :generation_run, :persist

      def detect_improvements(learning, comparison)
        benchmark = comparison.benchmark
        improvements = []
        append_low_metric(improvements, learning, benchmark, "cta_rate", "cta_improvement")
        append_high_metric(improvements, learning, benchmark, "bounce_rate", "first_view_improvement", nested: "ga4")
        append_low_metric(improvements, learning, benchmark, "engagement_seconds", "structure_improvement", nested: "ga4")
        append_low_metric(improvements, learning, benchmark, "form_submit_rate", "form_improvement")
        append_low_metric(improvements, learning, benchmark, "gsc_clicks_per_day", "seo_improvement", nested: "metrics")

        cvr = learning["cvr"]
        benchmark_cvr = benchmark["cvr"]
        if direct_metric_available?(learning) && materially_lower?(cvr, benchmark_cvr) && improvements.none? { |item| item.type == "cta_improvement" }
          improvements << improvement_for("design_improvement", cvr, benchmark_cvr, "CVR")
        end
        improvements
      end

      def append_low_metric(items, learning, benchmark, key, type, nested: nil)
        return if nested.in?(%w[ga4 metrics]) && !page_metric_available?(learning, nested)
        return if nested.nil? && key.in?(%w[cta_rate form_submit_rate]) && !direct_metric_available?(learning)

        current = nested ? learning.dig(nested, key) : learning[key]
        baseline = benchmark[key]
        items << improvement_for(type, current, baseline, label_for(key)) if materially_lower?(current, baseline)
      end

      def append_high_metric(items, learning, benchmark, key, type, nested: nil)
        return if nested.in?(%w[ga4 metrics]) && !page_metric_available?(learning, nested)

        current = nested ? learning.dig(nested, key) : learning[key]
        baseline = benchmark[key]
        items << improvement_for(type, current, baseline, label_for(key), high_is_bad: true) if materially_higher?(current, baseline)
      end

      def materially_lower?(current, baseline)
        current.present? && baseline.to_f.positive? && current.to_f <= baseline.to_f * (1 - PERFORMANCE_GAP_RATIO)
      end

      def materially_higher?(current, baseline)
        current.present? && baseline.to_f.positive? && current.to_f >= baseline.to_f * (1 + PERFORMANCE_GAP_RATIO)
      end

      def page_metric_available?(learning, nested)
        source = nested == "metrics" ? "gsc" : nested
        learning.dig(source, "available") == true && learning.dig(source, "scope") == "landing_page"
      end

      def direct_metric_available?(learning)
        learning["landing_page_events_available"] == true &&
          learning["direct_pageviews"].to_i >= LandingPageLearningComparison::MIN_PAGEVIEWS
      end

      def improvement_for(type, current, baseline, metric_label, high_is_bad: false)
        gap = if high_is_bad
          current.to_f / baseline.to_f - 1
        else
          1 - current.to_f / baseline.to_f
        end
        reason = "#{metric_label}が比較基準より#{(gap * 100).round}%#{high_is_bad ? '高い' : '低い'}（現在 #{format_metric(current)} / 基準 #{format_metric(baseline)}）"
        details = improvement_details(type)
        Improvement.new(
          type:,
          title: "#{business.name} #{details.fetch(:title)}",
          reason:,
          target_metric: details.fetch(:metric),
          current_value: current.to_f,
          benchmark_value: baseline.to_f,
          severity: gap.round(4),
          change_request: "現在#{generation_run.metadata.to_h['version_label']}をベースにしてください。#{reason}ため、#{details.fetch(:instruction)}。その他の構成・計測・レスポンシブ動作は維持してください。"
        )
      end

      def improvement_details(type)
        {
          "cta_improvement" => { title: "LPのCTAを改善する", metric: "cta_rate", instruction: "CTAのコピー、視認性、配置だけを改善してください" },
          "first_view_improvement" => { title: "LPのファーストビューを改善する", metric: "bounce_rate", instruction: "ファーストビューの価値訴求と主CTAだけを改善してください" },
          "structure_improvement" => { title: "LPの構成を改善する", metric: "engagement_seconds", instruction: "情報の順序、見出し、読み進めやすさを改善してください" },
          "form_improvement" => { title: "LPのフォームを改善する", metric: "form_submit_rate", instruction: "フォームの項目、説明、エラー表示、送信導線だけを改善してください" },
          "design_improvement" => { title: "LPのデザインを改善する", metric: "cvr", instruction: "CVRを妨げている視認性と情報設計を改善してください" },
          "seo_improvement" => { title: "LPのSEOを改善する", metric: "gsc_clicks_per_day", instruction: "title、description、見出し構造と検索意図への適合だけを改善してください" }
        }.fetch(type)
      end

      def materialize_candidates(improvements, learning, comparison)
        candidates = []
        duplicates = 0
        improvements.each do |improvement|
          existing = duplicate_candidate(improvement)
          if existing
            candidates << existing
            duplicates += 1
          elsif persist
            candidates << create_candidate!(improvement, learning, comparison)
          end
        end
        [ candidates, duplicates ]
      end

      def create_candidate!(improvement, learning, comparison)
        business.with_lock do
          duplicate_candidate(improvement) || business.action_candidates.create!(
            title: improvement.title,
            description: "公開LPのVersion Learningより生成。#{improvement.reason}",
            evaluation_reason: improvement.reason,
            action_type: "ui_improvement",
            status: "proposal",
            generation_source: GENERATION_SOURCE,
            department: "revenue",
            immediate_value_yen: projected_incremental_profit(learning, comparison),
            cost_yen: 0,
            expected_hours: ESTIMATED_WORK_HOURS.fetch(improvement.type),
            success_probability: learning["confidence"].to_f.clamp(0.01, 0.99),
            confidence_score: (learning["confidence"].to_f * 100).round.clamp(0, 100),
            data_confidence_score: (learning["confidence"].to_f * 100).round.clamp(0, 100),
            metadata: candidate_metadata(improvement, learning, comparison)
          )
        end
      end

      def candidate_metadata(improvement, learning, comparison)
        production_url = generation_run.metadata.to_h.dig("publication", "production_url")
        {
          "generation_source" => GENERATION_SOURCE,
          "source_system" => "lovable",
          "source_type" => "lp_learning",
          "data_sources_used" => data_sources_used(learning),
          "execution_mode" => "lovable_revision",
          "execution_readiness" => "blocked",
          "codex_eligible" => false,
          "auto_revision" => false,
          "auto_merge" => false,
          "auto_deploy" => false,
          "target_record_id" => generation_run.metadata.to_h["landing_page_id"],
          "production_url" => production_url,
          "target_metric" => improvement.target_metric,
          "current_version" => generation_run.metadata.to_h["version"],
          "best_version" => comparison.best&.run&.metadata.to_h&.dig("version"),
          "learning_id" => generation_run.id,
          "improvement_type" => improvement.type,
          "improvement_reason" => improvement.reason,
          "metrics" => learning["metrics"],
          "expected_roi" => comparison.best&.learning&.dig("roi") || comparison.benchmark["roi"],
          "confidence" => learning["confidence"],
          "benchmark_source" => comparison.benchmark_source,
          "lovable_change_request" => improvement.change_request,
          "next_action" => "Lovableで#{generation_run.metadata.to_h['version_label']}を基にPreviewを生成する",
          "concrete_task" => improvement.change_request,
          "recommended_action" => improvement.change_request,
          "completion_criteria" => [
            "Lovableで変更対象以外を維持したPreviewを生成する",
            "Before/Afterの差分とLearning根拠をOwnerが確認できる",
            "公開後に#{improvement.target_metric}をVersion単位で再計測する"
          ],
          "before" => "#{improvement.target_metric}=#{format_metric(improvement.current_value)}",
          "after" => "#{improvement.target_metric}=#{format_metric(improvement.benchmark_value)}以上を目標",
          "evidence" => {
            "source" => "lp_learning",
            "current_value" => improvement.current_value,
            "benchmark_value" => improvement.benchmark_value,
            "reason" => improvement.reason,
            "expected_effect" => "#{improvement.target_metric}を比較基準まで改善する"
          },
          "action_plan" => {
            "execution_mode" => "lovable_revision",
            "goal" => improvement.title,
            "summary" => improvement.change_request,
            "target" => "公開LP #{generation_run.metadata.to_h['version_label']}",
            "owner_output" => "Lovable PreviewのBefore/Afterを確認して公開判断する"
          },
          "lp_learning" => {
            "candidate_key" => candidate_key(improvement),
            "generation_run_id" => generation_run.id,
            "landing_page_id" => generation_run.metadata.to_h["landing_page_id"],
            "current_version" => generation_run.metadata.to_h["version"],
            "best_version" => comparison.best&.run&.metadata.to_h&.dig("version"),
            "learning_id" => generation_run.id,
            "improvement_type" => improvement.type,
            "improvement_reason" => improvement.reason,
            "metrics" => learning["metrics"],
            "expected_roi" => comparison.best&.learning&.dig("roi") || comparison.benchmark["roi"],
            "confidence" => learning["confidence"],
            "benchmark_source" => comparison.benchmark_source,
            "generated_at" => Time.current.iso8601
          }
        }
      end

      def duplicate_candidate(improvement)
        business.action_candidates.where(generation_source: GENERATION_SOURCE).active_for_ranking.find do |candidate|
          candidate.metadata.to_h.dig("lp_learning", "candidate_key") == candidate_key(improvement)
        end
      end

      def candidate_key(improvement)
        Digest::SHA256.hexdigest([ business.id, generation_run.id, improvement.type ].join(":"))
      end

      def projected_incremental_profit(learning, comparison)
        current_cvr = learning["cvr"].to_f
        benchmark_cvr = comparison.benchmark["cvr"].to_f
        additional_conversions = [ (benchmark_cvr - current_cvr) * learning["pageviews"].to_i, 0 ].max
        value_per_conversion = observed_value_per_conversion(learning, comparison)
        (additional_conversions * value_per_conversion).round
      end

      def observed_value_per_conversion(learning, comparison)
        candidates = [ learning, comparison.best&.learning ].compact
        candidates.each do |metrics|
          conversions = metrics["conversions"].to_i
          return metrics["revenue_yen"].to_d / conversions if conversions.positive? && metrics["revenue_yen"].to_d.positive?
        end
        0.to_d
      end

      def data_sources_used(learning)
        sources = %w[lp_learning landing_page_events]
        sources << "ga4" if learning.dig("ga4", "available") == true
        sources << "gsc" if learning.dig("gsc", "available") == true
        sources
      end

      def persist_analysis!(learning:, comparison:, improvements:, status:, skip_reason:)
        return unless persist

        generation_run.update!(metadata: generation_run.metadata.to_h.merge(
          "learning" => learning,
          "landing_page_improvement_analysis" => {
            "status" => status,
            "skip_reason" => skip_reason,
            "benchmark_source" => comparison.benchmark_source,
            "benchmark" => comparison.benchmark,
            "best_version" => comparison.best&.run&.metadata.to_h&.dig("version"),
            "worst_version" => comparison.worst&.run&.metadata.to_h&.dig("version"),
            "improvement_success_rate" => comparison.improvement_success_rate,
            "version_trend" => comparison.version_trend,
            "improvements" => improvements.map(&:to_h),
            "analyzed_at" => Time.current.iso8601
          }.compact
        ))
      end

      def empty_result(reason)
        Result.new(
          business:,
          generation_run: nil,
          learning: {},
          comparison: nil,
          analysis_status: "skipped",
          improvements: [],
          candidates: [],
          duplicate_count: 0,
          skip_reason: reason
        )
      end

      def result(learning:, comparison:, improvements:, candidates:, duplicate_count:, status:, skip_reason:)
        Result.new(
          business:,
          generation_run:,
          learning:,
          comparison:,
          analysis_status: status,
          improvements:,
          candidates:,
          duplicate_count:,
          skip_reason:
        )
      end

      def label_for(key)
        {
          "cta_rate" => "CTAクリック率",
          "bounce_rate" => "離脱率",
          "engagement_seconds" => "平均滞在時間",
          "form_submit_rate" => "フォーム送信率",
          "gsc_clicks_per_day" => "検索クリック/日"
        }.fetch(key, key)
      end

      def format_metric(value)
        value.to_f.round(4)
      end
    end
  end
end
