module Aicoo
  class ActivityLearningE2eCheck
    Check = Struct.new(:key, :label, :status, :message, :repair_action, keyword_init: true) do
      def pass?
        status == "pass"
      end

      def warning?
        status == "warning"
      end

      def fail?
        status == "fail"
      end
    end

    Result = Struct.new(:business, :checks, :summary, :generated_at, keyword_init: true) do
      def status
        return "fail" if checks.any?(&:fail?)
        return "warning" if checks.any?(&:warning?)

        "pass"
      end

      def pass_count
        checks.count(&:pass?)
      end

      def warning_count
        checks.count(&:warning?)
      end

      def fail_count
        checks.count(&:fail?)
      end
    end

    def initialize(business)
      @business = business
    end

    def call
      checks = [
        source_app_connection_check,
        source_app_diff_rule_check,
        cursor_check,
        activity_detection_check,
        shop_db_change_detection_check,
        db_diff_activity_check,
        logger_activity_check,
        unlinked_activity_check,
        evaluation_status_check,
        activity_evaluation_check,
        metric_linkage_check,
        daily_run_step_check("source_app_diff_detection", "Daily Run: Source App差分検知"),
        daily_run_step_check("activity_log_evaluation_queue_build", "Daily Run: Activity評価キュー")
      ]

      Result.new(
        business:,
        checks:,
        summary: summary_for(checks),
        generated_at: Time.current
      )
    end

    def self.repair!(business, action)
      new(business).repair!(action)
    end

    def repair!(action)
      case action.to_s
      when "activate_connections"
        activate_connections!
      when "activate_rules"
        activate_rules!
      when "create_cursors"
        create_cursors!
      when "build_evaluations"
        Aicoo::ActivityEvaluationTrigger.call(business:, invoked_by: "Manual")
      when "rerun_daily_steps"
        rerun_daily_steps!
      else
        raise ArgumentError, "未対応の復旧操作です"
      end
    end

    private

    attr_reader :business

    def source_app_connection_check
      active_count = connections.enabled.active.count
      if active_count.positive?
        pass("source_app_connection", "SourceAppConnection active", "#{active_count}件 active です")
      elsif connections.exists?
        fail("source_app_connection", "SourceAppConnection active", "接続はありますが無効またはerrorです", "activate_connections")
      else
        warning("source_app_connection", "SourceAppConnection active", "接続がありません。必要なら復旧で標準接続を作成します。", "activate_connections")
      end
    end

    def source_app_diff_rule_check
      active_count = rules.enabled.count
      if active_count.positive?
        pass("source_app_diff_rule", "SourceAppDiffRule active", "#{active_count}件 active です")
      elsif rules.exists?
        fail("source_app_diff_rule", "SourceAppDiffRule active", "Diff Ruleはありますが無効です", "activate_rules")
      else
        warning("source_app_diff_rule", "SourceAppDiffRule active", "Diff Ruleがありません。Source別に追加してください。")
      end
    end

    def cursor_check
      missing_count = rules.enabled.left_outer_joins(:source_app_diff_cursor).where(source_app_diff_cursors: { id: nil }).count
      if rules.enabled.none?
        warning("cursor", "cursor存在", "activeなDiff Ruleがまだありません。")
      elsif missing_count.zero?
        pass("cursor", "cursor存在", "すべてのactive Diff Ruleにcursorがあります")
      else
        fail("cursor", "cursor存在", "#{missing_count}件のcursorがありません", "create_cursors")
      end
    end

    def activity_detection_check
      today_count = activity_logs.where(occurred_at: Time.current.all_day).count
      week_count = activity_logs.where(occurred_at: 7.days.ago..Time.current).count
      if today_count.positive?
        pass("activity_detection", "今日/直近7日Activity検知あり", "今日#{today_count}件 / 7日#{week_count}件")
      elsif week_count.positive?
        warning("activity_detection", "今日/直近7日Activity検知あり", "今日0件 / 7日#{week_count}件")
      else
        fail("activity_detection", "今日/直近7日Activity検知あり", "直近7日のActivityがありません", "rerun_daily_steps")
      end
    end

    def db_diff_activity_check
      count = activity_logs.where(source_method: "db_diff").count
      count.positive? ? pass("db_diff_activity", "source_method=db_diff", "#{count}件") : warning("db_diff_activity", "source_method=db_diff", "DB差分由来のActivityがありません", "rerun_daily_steps")
    end

    def shop_db_change_detection_check
      shop_rule_exists = rules.where(resource_type: "Shop").exists?
      shop_activity_count = activity_logs.where(resource_type: "Shop").where(occurred_at: 7.days.ago..Time.current).count

      if shop_activity_count.positive?
        pass("shop_db_change_detection", "Shop DB変更検知", "直近7日でShop Activity #{shop_activity_count}件")
      elsif shop_rule_exists
        warning("shop_db_change_detection", "Shop DB変更検知", "Shop検知ルールはありますが、直近7日のShop Activityはありません", "rerun_daily_steps")
      else
        fail("shop_db_change_detection", "Shop DB変更検知", "Shop作成/更新を拾うDiff Ruleがありません", "activate_rules")
      end
    end

    def logger_activity_check
      count = activity_logs.where(source_method: "logger").count
      count.positive? ? pass("logger_activity", "source_method=logger", "#{count}件") : warning("logger_activity", "source_method=logger", "Logger由来のActivityがありません")
    end

    def unlinked_activity_check
      count = AicooActivityLogQueue.pending.where("metadata ->> 'unlinked_activity' = ?", "true").count
      return pass("unlinked_activity", "未紐付けActivity", "未紐付けActivityはありません") if count.zero?

      warning("unlinked_activity", "未紐付けActivity", "Businessに紐付けできないActivityが#{count}件あります")
    end

    def evaluation_status_check
      counts = activity_logs.group(:evaluation_status).count
      total = counts.values.sum
      if total.positive?
        pass(
          "evaluation_status",
          "evaluation_status件数",
          "pending #{counts['pending'].to_i} / evaluating #{counts['evaluating'].to_i} / evaluated #{counts['evaluated'].to_i}"
        )
      else
        warning("evaluation_status", "evaluation_status件数", "Activityがないため評価状態もありません")
      end
    end

    def activity_evaluation_check
      count = business.activity_evaluations.count
      due_count = activity_logs.evaluation_due.where("occurred_at <= ?", 7.days.ago).count
      if count.positive?
        pass("activity_evaluation", "ActivityEvaluation作成可否", "#{count}件作成済み")
      elsif due_count.positive?
        fail("activity_evaluation", "ActivityEvaluation作成可否", "評価可能なActivityが#{due_count}件ありますがEvaluation未作成です", "build_evaluations")
      else
        warning("activity_evaluation", "ActivityEvaluation作成可否", "評価期間待ち、またはMetric不足です")
      end
    end

    def metric_linkage_check
      metric_counts = {
        gsc: business.business_metric_dailies.where("impressions > 0 OR clicks > 0").count,
        ga4: business.business_metric_dailies.where("sessions > 0 OR pageviews > 0 OR users > 0").count,
        clicks: business.business_metric_dailies.where("phone_clicks > 0 OR map_clicks > 0 OR affiliate_clicks > 0").count,
        revenue: business.revenue_events.revenue.count
      }
      present_count = metric_counts.values.count(&:positive?)
      message = "GSC #{metric_counts[:gsc]} / GA4 #{metric_counts[:ga4]} / クリック #{metric_counts[:clicks]} / Revenue #{metric_counts[:revenue]}"
      return pass("metric_linkage", "GA4/GSC/クリック/RevenueEvent紐付け", message) if present_count >= 2
      return warning("metric_linkage", "GA4/GSC/クリック/RevenueEvent紐付け", message) if present_count == 1

      fail("metric_linkage", "GA4/GSC/クリック/RevenueEvent紐付け", "評価に使う計測データがありません")
    end

    def daily_run_step_check(step_name, label)
      step = AicooDailyRunStep.joins(:aicoo_daily_run)
                              .where(step_name:)
                              .merge(AicooDailyRun.recent)
                              .order("aicoo_daily_runs.started_at DESC NULLS LAST", "aicoo_daily_run_steps.created_at DESC")
                              .first
      return warning(step_name, label, "まだ実行履歴がありません", "rerun_daily_steps") unless step
      return pass(step_name, label, "直近はsuccessです") if step.status == "success"

      fail(step_name, label, "直近は#{step.status}: #{step.error_message.presence || '詳細なし'}", "rerun_daily_steps")
    end

    def pass(key, label, message)
      Check.new(key:, label:, status: "pass", message:)
    end

    def warning(key, label, message, repair_action = nil)
      Check.new(key:, label:, status: "warning", message:, repair_action:)
    end

    def fail(key, label, message, repair_action = nil)
      Check.new(key:, label:, status: "fail", message:, repair_action:)
    end

    def connections
      business.source_app_connections
    end

    def rules
      SourceAppDiffRule.joins(:source_app_connection).where(source_app_connections: { business_id: business.id })
    end

    def activity_logs
      business.business_activity_logs
    end

    def activate_connections!
      if connections.none?
        connections.create!(
          name: "#{business.name} Source App",
          source_app: business.project_key.presence || business.name.parameterize.presence || "business_#{business.id}",
          connection_type: "same_database",
          enabled: true,
          status: "active"
        )
      else
        connections.update_all(enabled: true, status: "active", updated_at: Time.current)
      end
    end

    def activate_rules!
      SourceAppConnection.ensure_suelog_defaults! if business.name == "吸えログ"
      rules.update_all(enabled: true, updated_at: Time.current)
    end

    def create_cursors!
      rules.enabled.find_each { |rule| rule.cursor }
    end

    def rerun_daily_steps!
      Aicoo::SourceAppDiffDetector.new.call
      Aicoo::ActivityEvaluationTrigger.call(business:, invoked_by: "Manual")
    end

    def summary_for(checks)
      fail_count = checks.count(&:fail?)
      warning_count = checks.count(&:warning?)
      return "Activity Learningは評価まで進める状態です。" if fail_count.zero? && warning_count.zero?
      return "復旧が必要な項目が#{fail_count}件あります。" if fail_count.positive?

      "動作は可能ですが、確認したい項目が#{warning_count}件あります。"
    end
  end
end
