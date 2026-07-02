module Aicoo
  module Serp
    class E2eCheck
      Check = Data.define(:key, :label, :status, :message, :repair_action, :details)
      Result = Data.define(:business, :checks, :scan_plan_keywords, :latest_analysis, :serp_candidates, :daily_run_steps, :generated_at) do
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
          daily_run_steps:,
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
          Aicoo::Serp::ScanRunner.new(target_businesses: [ business ]).call
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
          daily_run_check
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
          gsc_count: keyword_scope.where(source: "gsc").count
        )
        return check(:keywords, "Keyword診断", "pass", "Active keywordが#{counts.fetch('active', 0)}件あります。", details:) if counts.fetch("active", 0).positive?
        if counts.fetch("pending", 0).positive?
          return check(:keywords, "Keyword診断", "warning", "Pending keywordだけ存在します。承認すると取得対象になります。", repair_action: "approve_pending_keywords", details:)
        end

        check(:keywords, "Keyword診断", "fail", "Active keywordが0件です。", repair_action: "regenerate_keyword_suggestions", details:)
      end

      def scan_plan_check
        details = {
          planned_count: scan_plan_keywords.size,
          keywords: scan_plan_keywords,
          priority_order: active_keywords.map { |keyword| { keyword: keyword.keyword, priority_score: keyword.priority_score } }
        }
        return check(:scan_plan, "Scan Plan", "pass", "今日取得予定は#{scan_plan_keywords.size}件です。", details:) if scan_plan_keywords.any?

        check(:scan_plan, "Scan Plan", "fail", "取得予定キーワードがありません。", repair_action: "regenerate_keyword_suggestions", details:)
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
        return check(:serp_result, "SERP取得結果", "fail", "SERP取得結果がありません。", repair_action: "run_serp_scan") unless latest_analysis
        return check(:serp_result, "SERP取得結果", "fail", "SERP成功結果がありません。", repair_action: "run_serp_scan") unless latest_analysis.successful?

        details = {
          title_count: latest_analysis.serp_results.where.not(title: [ nil, "" ]).count,
          url_count: latest_analysis.serp_results.where.not(url: [ nil, "" ]).count,
          related_searches_count: latest_analysis.raw_summary.to_h.fetch("related_searches", []).size,
          people_also_ask_count: latest_analysis.raw_summary.to_h.fetch("people_also_ask_count", 0)
        }
        return check(:serp_result, "SERP取得結果", "pass", "SERP結果が保存されています。", details:) if latest_analysis.serp_results.exists?

        check(:serp_result, "SERP取得結果", "fail", "SERP分析はsuccessですが、serp_resultsが0件です。", repair_action: "run_serp_scan", details:)
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
          return check(:action_candidate, "Action Candidate", "fail", "SERP成功済みですが候補が0件です。", repair_action: "regenerate_action_candidates", details:)
        end

        check(:action_candidate, "Action Candidate", "warning", "SERP由来候補はまだありません。", details:)
      end

      def daily_run_check
        details = daily_run_steps.map do |step|
          {
            run_id: step.aicoo_daily_run_id,
            step_name: step.step_name,
            status: step.status,
            reason: step.metadata.to_h["reason"],
            message: step.metadata.to_h["message"] || step.error_message
          }
        end
        failed = daily_run_steps.any? { |step| step.status == "failed" }
        running = daily_run_steps.any? { |step| step.status == "running" }
        skipped = daily_run_steps.any? { |step| step.status == "skipped" }
        return check(:daily_run, "Daily Run", "fail", "SERP関連stepにfailedがあります。", details:) if failed
        return check(:daily_run, "Daily Run", "warning", "SERP関連stepがrunningです。", details:) if running
        return check(:daily_run, "Daily Run", "warning", "SERP関連stepはskippedです。理由を確認してください。", details:) if skipped
        return check(:daily_run, "Daily Run", "pass", "SERP関連stepは実行済みです。", details:) if daily_run_steps.any?

        check(:daily_run, "Daily Run", "warning", "SERP関連step履歴がありません。", details:)
      end

      def keyword_scope
        @keyword_scope ||= business.business_serp_keywords
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

      def daily_run_steps
        @daily_run_steps ||= AicooDailyRunStep
          .joins(:aicoo_daily_run)
          .where(step_name: Aicoo::Serp::OptionalMode::SERP_DEPENDENT_STEPS)
          .where("aicoo_daily_runs.created_at >= ?", 30.days.ago)
          .order(created_at: :desc)
          .limit(12)
          .to_a
      end

      def latest_skipped_step_count
        daily_run_steps.count { |step| step.status == "skipped" }
      end

      def check(key, label, status, message, repair_action: nil, details: {})
        Check.new(key:, label:, status:, message:, repair_action:, details:)
      end
    end
  end
end
