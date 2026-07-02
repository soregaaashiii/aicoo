module Aicoo
  module Serp
    class E2eCheck
      Check = Data.define(:key, :label, :status, :message, :repair_action, :details)
      Result = Data.define(:business, :checks, :scan_plan_keywords, :latest_analysis, :serp_candidates, :serp_runs, :pipeline_metrics, :generated_at) do
        def overall_status
          return "broken" if checks.any? { |check| check.status == "fail" }
          return "warning" if checks.any? { |check| check.status == "warning" }

          "healthy"
        end

        def health_label
          { "healthy" => "Healthy", "warning" => "Warning", "broken" => "Broken" }.fetch(overall_status)
        end

        def first_problem
          checks.find { |check| check.status == "fail" } || checks.find { |check| check.status == "warning" }
        end

        def repairable_checks
          checks.select { |check| check.repair_action.present? }
        end
      end

      SAFE_REPAIR_ACTIONS = %w[
        approve_pending_keywords
        regenerate_keyword_suggestions
        run_serp_scan
        regenerate_action_candidates
      ].freeze

      def self.repair!(business:, action:)
        action = action.to_s
        raise ArgumentError, "復旧できない操作です。" unless action.in?(SAFE_REPAIR_ACTIONS)

        new(business).repair!(action)
      end

      def initialize(business)
        @business = business
      end

      def call
        Result.new(
          business:,
          checks: build_checks,
          scan_plan_keywords:,
          latest_analysis:,
          serp_candidates:,
          serp_runs:,
          pipeline_metrics:,
          generated_at: Time.current
        )
      end

      def repair!(action)
        case action.to_s
        when "approve_pending_keywords"
          business.business_serp_keywords.pending.find_each(&:activate!)
        when "regenerate_keyword_suggestions"
          Aicoo::Serp::KeywordManager.generate_suggestions!(business:)
        when "run_serp_scan"
          Aicoo::Serp::RunExecutor.new(executed_by: "manual", force: true).call
        when "regenerate_action_candidates"
          MetricActionCandidateGenerator.new(business:).call
        end
        call
      end

      private

      attr_reader :business

      def build_checks
        [
          api_check,
          business_setting_check,
          keyword_check,
          scan_plan_check,
          scan_execution_check,
          serp_result_check,
          learning_check,
          action_candidate_check,
          serp_run_check
        ]
      end

      def api_check
        optional = Aicoo::Serp::OptionalMode.call
        details = { provider: optional.provider, optional_status: optional.status, reason: optional.reason }
        return check(:serp_api, "SERP API", "pass", "API Key設定済みです。", details:) if optional.api_key_configured
        return check(:serp_api, "SERP API", "warning", optional.message, details:) if optional.missing_key?

        check(:serp_api, "SERP API", "warning", "SERPは無効です。SERP依存stepだけ停止します。", details:)
      end

      def business_setting_check
        return check(:business_setting, "Business設定", "fail", "Businessが存在しません。") unless business
        return check(:business_setting, "Business設定", "fail", "SERPがOFFです。", details: { business_id: business.id }) unless business.serp_enabled?

        setting = business.business_data_source_settings.find { |row| row.source_key == "serp" }
        status = setting ? "Data Source設定あり" : "Data Source設定なし。active keywordがあれば取得可能です。"
        check(:business_setting, "Business設定", "pass", "SERP有効です。#{status}", details: { business_id: business.id, data_source_setting_id: setting&.id })
      end

      def keyword_check
        counts = keyword_counts
        details = counts.merge(
          manual_count: keyword_scope.where(source: "manual").count,
          ai_suggested_count: keyword_scope.where(source: "ai_suggested").count,
          gsc_count: keyword_scope.where(source: "gsc").count,
          active_query_count: query_scope.enabled.count,
          archived_query_count: query_scope.where(status: "archived").count
        )
        return check(:keywords, "検索クエリ診断", "pass", "Active検索クエリが#{query_scope.enabled.count}件あります。", details:) if query_scope.enabled.exists?
        return check(:keywords, "検索クエリ診断", "pass", "Active keywordが#{counts.fetch('active', 0)}件あります。", details:) if counts.fetch("active", 0).positive?
        if counts.fetch("pending", 0).positive?
          return check(:keywords, "検索クエリ診断", "warning", "Pending検索クエリだけ存在します。承認すると取得対象になります。", repair_action: "approve_pending_keywords", details:)
        end

        check(:keywords, "検索クエリ診断", "fail", "Active検索クエリが0件です。", repair_action: "regenerate_keyword_suggestions", details:)
      end

      def scan_plan_check
        details = {
          planned_count: scan_plan_keywords.size,
          keywords: scan_plan_keywords,
          priority_order: query_scope.enabled.by_priority.limit(10).map { |query| { query: query.query, priority: query.priority } }
        }
        return check(:scan_plan, "Scan Plan", "pass", "今日取得予定は#{scan_plan_keywords.size}件です。", details:) if scan_plan_keywords.any?

        check(:scan_plan, "Scan Plan", "fail", "取得予定の検索クエリがありません。", repair_action: "regenerate_keyword_suggestions", details:)
      end

      def scan_execution_check
        return check(:scan_execution, "Scan実行結果", "warning", "SERP取得はまだ実行されていません。", repair_action: "run_serp_scan") unless latest_analysis

        latest_batch = latest_batch_analyses
        failed = latest_batch.count(&:failed?)
        success = latest_batch.count(&:successful?)
        running = latest_batch.count(&:running?)
        details = {
          analyzed_at: latest_analysis.analyzed_at,
          success_count: success,
          skip_count: latest_skipped_step_count,
          error_count: failed,
          running_count: running,
          error_message: latest_batch.find(&:failed?)&.error_message,
          stack_trace: latest_batch.find(&:failed?)&.raw_summary.to_h.slice("error_class", "error_message"),
          recovery: failed.positive? ? "API Key、Provider、Rate Limitを確認し、今すぐ取得を再実行してください。" : nil
        }
        return check(:scan_execution, "Scan実行結果", "fail", "SERP取得でエラーがあります。", repair_action: "run_serp_scan", details:) if failed.positive?
        return check(:scan_execution, "Scan実行結果", "warning", "SERP取得が実行中です。", details:) if running.positive?

        check(:scan_execution, "Scan実行結果", "pass", "直近SERP取得は成功しています。", details:)
      end

      def serp_result_check
        unless latest_analysis
          return check(
            :serp_result,
            "SERP取得結果",
            "fail",
            "選択BusinessのSerpAnalysis保存0件です。SERP Runは成功していても、このBusinessには解析結果が紐付いていません。",
            repair_action: "run_serp_scan",
            details: pipeline_metrics.merge(fail_reason: "business_serp_analysis_missing")
          )
        end
        unless latest_analysis.successful?
          return check(
            :serp_result,
            "SERP取得結果",
            "fail",
            "選択BusinessのSERP成功結果がありません。最後の解析status=#{latest_analysis.status}です。",
            repair_action: "run_serp_scan",
            details: pipeline_metrics.merge(fail_reason: "business_serp_analysis_not_success", latest_status: latest_analysis.status, latest_error: latest_analysis.error_message)
          )
        end

        details = {
          title_count: latest_analysis.serp_results.where.not(title: [ nil, "" ]).count,
          url_count: latest_analysis.serp_results.where.not(url: [ nil, "" ]).count,
          related_searches_count: latest_analysis.raw_summary.to_h.fetch("related_searches", []).size,
          people_also_ask_count: latest_analysis.raw_summary.to_h.fetch("people_also_ask_count", 0)
        }
        return check(:serp_result, "SERP取得結果", "pass", "SERP結果が保存されています。", details:) if latest_analysis.serp_results.exists?

        check(
          :serp_result,
          "SERP取得結果",
          "fail",
          "SerpResult保存0件です。SerpAnalysisはsuccessですが、検索結果行が保存されていません。",
          repair_action: "run_serp_scan",
          details: details.merge(pipeline_metrics).merge(fail_reason: "serp_result_missing")
        )
      end

      def learning_check
        details = {
          pending_keywords: keyword_scope.pending.count,
          checked_keywords: keyword_scope.where.not(last_checked_at: nil).count,
          opportunity_keywords: keyword_scope.where.not(opportunity_score: nil).count
        }
        return check(:learning, "Learning", "pass", "Keyword更新が進んでいます。", details:) if details[:checked_keywords].positive? || details[:pending_keywords].positive?

        check(:learning, "Learning", "warning", "Keyword生成・更新がまだありません。", repair_action: "regenerate_keyword_suggestions", details:)
      end

      def action_candidate_check
        details = {
          candidate_count: serp_candidates.count,
          titles: serp_candidates.limit(5).pluck(:title),
          latest_created_at: serp_candidates.maximum(:created_at)
        }
        if serp_candidates.exists?
          return check(:action_candidate, "Action Candidate", "pass", "SERP由来候補が#{serp_candidates.count}件あります。", details:)
        end
        if latest_analysis&.successful?
          reason =
            if pipeline_metrics[:business_result_count].zero?
              "SerpResult保存0件のためCandidate生成材料がありません。"
            else
              "Candidate生成件数0件です。候補生成ルール未達、OpenAI失敗、またはMetricActionCandidateGeneratorのSERP分岐を確認してください。"
            end
          return check(
            :action_candidate,
            "Action Candidate",
            "fail",
            "SERP成功済みですが候補が0件です。#{reason}",
            repair_action: "regenerate_action_candidates",
            details: details.merge(pipeline_metrics).merge(fail_reason: "serp_candidate_missing")
          )
        end

        check(:action_candidate, "Action Candidate", "warning", "SERP由来候補はまだありません。", details:)
      end

      def serp_run_check
        details = serp_runs.map do |run|
          {
            run_id: run.id,
            status: run.status,
            executed_by: run.executed_by,
            query_count: run.query_count,
            success_count: run.success_count,
            failure_count: run.failure_count,
            message: run.error_message
          }
        end
        failed = serp_runs.any? { |run| run.status == "failed" }
        running = serp_runs.any? { |run| run.status == "running" }
        partial = serp_runs.any? { |run| run.status == "partial_failed" }
        return check(:serp_run, "SERP Run", "fail", "SERP Runにfailedがあります。", details:) if failed
        return check(:serp_run, "SERP Run", "warning", "SERP Runがrunningです。", details:) if running
        return check(:serp_run, "SERP Run", "warning", "SERP Runにpartial_failedがあります。", details:) if partial
        return check(:serp_run, "SERP Run", "pass", "SERP専用Runは保存されています。", details:) if serp_runs.any?

        check(:serp_run, "SERP Run", "warning", "SERP専用Run履歴がありません。", details:)
      end

      def keyword_scope
        @keyword_scope ||= business.business_serp_keywords
      end

      def query_scope
        @query_scope ||= business.serp_queries
      end

      def keyword_counts
        @keyword_counts ||= keyword_scope.group(:status).count
      end

      def active_keywords
        @active_keywords ||= keyword_scope.fetchable.to_a
      end

      def scan_plan_keywords
        @scan_plan_keywords ||= Aicoo::Serp::ScanRunner.queries_for_business(business)
      end

      def latest_analysis
        @latest_analysis ||= business.serp_analyses.order(analyzed_at: :desc, created_at: :desc).first
      end

      def latest_batch_analyses
        @latest_batch_analyses ||= begin
          batch_id = latest_analysis&.raw_summary.to_h["scan_batch_id"]
          if batch_id.present?
            business.serp_analyses.where("raw_summary ->> 'scan_batch_id' = ?", batch_id).to_a
          elsif latest_analysis
            [ latest_analysis ]
          else
            []
          end
        end
      end

      def serp_candidates
        @serp_candidates ||= business.action_candidates.where(generation_source: "serp").order(created_at: :desc)
      end

      def serp_runs
        @serp_runs ||= SerpRun.recent.limit(12).to_a
      end

      def latest_serp_run
        @latest_serp_run ||= serp_runs.first
      end

      def latest_run_analyses
        @latest_run_analyses ||= latest_serp_run ? latest_serp_run.serp_analyses.includes(:serp_results).to_a : []
      end

      def latest_run_business_analyses
        @latest_run_business_analyses ||= latest_run_analyses.select { |analysis| analysis.business_id == business.id }
      end

      def pipeline_metrics
        @pipeline_metrics ||= begin
          run_analyses = latest_run_analyses
          business_analyses = latest_run_business_analyses
          run_result_count = run_analyses.sum { |analysis| analysis.serp_results.size }
          business_result_count = business_analyses.sum { |analysis| analysis.serp_results.size }
          candidate_scope = latest_serp_run ? serp_candidates.where(created_at: latest_serp_run.started_at..Time.current) : serp_candidates

          {
            latest_serp_run_id: latest_serp_run&.id,
            latest_serp_run_status: latest_serp_run&.status,
            fetched_query_count: latest_serp_run&.query_count.to_i,
            saved_analysis_count: run_analyses.size,
            saved_result_count: run_result_count,
            business_analysis_count: business_analyses.size,
            business_result_count:,
            parsed_result_count: run_result_count,
            candidate_count: candidate_scope.count,
            latest_run_started_at: latest_serp_run&.started_at,
            latest_run_finished_at: latest_serp_run&.finished_at
          }
        end
      end

      def latest_skipped_step_count
        0
      end

      def check(key, label, status, message, repair_action: nil, details: {})
        Check.new(key:, label:, status:, message:, repair_action:, details:)
      end
    end
  end
end
