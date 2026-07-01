module Aicoo
  class PipelineE2eCheck
    Check = Data.define(:key, :label, :status, :message, :repair_action, :details)
    Result = Data.define(
      :pipeline_run,
      :idea_item,
      :business,
      :landing_page,
      :checks,
      :auto_revision_loop_checks,
      :generated_at
    ) do
      def overall_status
        all_checks = checks + auto_revision_loop_checks
        return "fail" if all_checks.any? { |check| check.status == "fail" }
        return "warning" if all_checks.any? { |check| check.status == "warning" }

        "pass"
      end

      def fail?
        overall_status == "fail"
      end

      def warning?
        overall_status == "warning"
      end

      def pass?
        overall_status == "pass"
      end

      def repairable_checks
        checks.select { |check| check.repair_action.present? }
      end

      def auto_revision_stop_point
        auto_revision_loop_checks.find { |check| check.status != "pass" }
      end

      def display_title
        idea_item&.title.presence || business&.name.presence || landing_page&.headline.presence || "Pipeline ##{pipeline_run&.id}"
      end
    end

    SAFE_REPAIR_ACTIONS = %w[
      create_business
      link_landing_page
      enable_daily_run
      enable_serp
    ].freeze

    def self.default_run
      AicooPipelineRun.includes(:business, :idea_pipeline_item, :aicoo_lab_landing_page).recent.find do |run|
        run.idea_pipeline_item || run.business || run.aicoo_lab_landing_page
      end || sync_latest_run
    end

    def self.failing_results(limit: 5)
      runs = AicooPipelineRun.includes(:business, :idea_pipeline_item, :aicoo_lab_landing_page).recent.limit(50)
      runs.filter_map do |run|
        result = new(run).call
        result if result.fail?
      end.first(limit)
    end

    def self.repair!(pipeline_run:, action:)
      action = action.to_s
      raise ArgumentError, "復旧できない操作です。" unless action.in?(SAFE_REPAIR_ACTIONS)

      new(pipeline_run).repair!(action)
    end

    def self.sync_latest_run
      item = IdeaPipelineItem.recent.first
      return Aicoo::PipelineEngine.new(item).call if item

      business = Business.real_businesses.order(updated_at: :desc).first
      business ? Aicoo::PipelineEngine.new(business).call : nil
    end

    def initialize(pipeline_run = nil)
      @pipeline_run = pipeline_run || self.class.default_run
    end

    def call
      Result.new(
        pipeline_run:,
        idea_item:,
        business:,
        landing_page:,
        checks: build_checks,
        auto_revision_loop_checks: build_auto_revision_loop_checks,
        generated_at: Time.current
      )
    end

    def repair!(action)
      case action.to_s
      when "create_business"
        repair_business!
      when "link_landing_page"
        repair_landing_page_link!
      when "enable_daily_run"
        require_business!.update!(daily_run_enabled: true)
      when "enable_serp"
        require_business!.update!(serp_enabled: true)
      end

      clear_memoized_subjects
      Aicoo::PipelineEngine.new(idea_item || business).call if idea_item || business
      call
    end

    private

    attr_reader :pipeline_run

    def idea_item
      @idea_item ||= pipeline_run&.idea_pipeline_item
    end

    def business
      @business ||= pipeline_run&.business || idea_item&.business || landing_page&.business
    end

    def landing_page
      @landing_page ||= pipeline_run&.aicoo_lab_landing_page ||
                        idea_item&.aicoo_lab_landing_page ||
                        business&.aicoo_lab_landing_pages&.order(updated_at: :desc)&.first ||
                        AicooLabLandingPage.publicly_available.where(business_id: nil).order(updated_at: :desc).first
    end

    def build_checks
      [
        idea_approval_check,
        business_created_check,
        business_listed_check,
        lp_generated_check,
        lp_published_check,
        lp_business_link_check,
        sitemap_check,
        google_measurement_check,
        daily_run_check,
        serp_check,
        improvement_check,
        auto_revision_queue_check
      ]
    end

    def idea_approval_check
      return check(:idea_approval, "Idea承認", "warning", "Idea Pipelineが未選択です。") unless idea_item
      return check(:idea_approval, "Idea承認", "pass", "承認または公開済みです。") if idea_approved?

      check(:idea_approval, "Idea承認", "fail", "Ideaがまだ承認されていません。")
    end

    def business_created_check
      return check(:business_created, "Business作成", "pass", "Business ##{business.id} が存在します。") if business

      check(:business_created, "Business作成", "fail", "Businessが未作成です。", repair_action: "create_business")
    end

    def business_listed_check
      return check(:business_listed, "Business一覧表示", "fail", "Businessがないため一覧表示できません。", repair_action: "create_business") unless business
      return check(:business_listed, "Business一覧表示", "pass", "/businesses に表示対象です。") if business_visible?

      check(
        :business_listed,
        "Business一覧表示",
        "fail",
        "Businessは存在しますが、実事業一覧の条件から外れています。",
        details: business_visibility_details
      )
    end

    def lp_generated_check
      return check(:lp_generated, "LP生成", "pass", "LP ##{landing_page.id} が存在します。") if landing_page

      check(:lp_generated, "LP生成", "fail", "LandingPageが未作成です。")
    end

    def lp_published_check
      return check(:lp_published, "LP公開", "fail", "LandingPageが未作成です。") unless landing_page
      return check(:lp_published, "LP公開", "pass", "公開LPとして表示できます。") if landing_page.publicly_visible?

      check(:lp_published, "LP公開", "warning", "LPはありますが published ではありません。")
    end

    def lp_business_link_check
      return check(:lp_business_link, "LPとBusiness紐付け", "warning", "LPが未作成です。") unless landing_page
      return check(:lp_business_link, "LPとBusiness紐付け", "pass", "LPにBusinessが紐付いています。") if landing_page.business_id.present?

      check(:lp_business_link, "LPとBusiness紐付け", "fail", "LPにbusiness_idがありません。", repair_action: "link_landing_page")
    end

    def sitemap_check
      return check(:sitemap, "sitemap反映", "fail", "公開LPがないためsitemap対象外です。") unless landing_page&.publicly_visible?
      return check(:sitemap, "sitemap反映", "pass", "published LPとしてsitemap対象です。") if AicooLabLandingPage.publicly_available.exists?(id: landing_page.id)

      check(:sitemap, "sitemap反映", "fail", "公開条件を満たさずsitemapに入りません。")
    end

    def google_measurement_check
      return check(:google_measurement, "Google計測設定", "fail", "公開LPがないためGA4/GSC対象になりません。") unless landing_page&.publicly_visible?
      return check(:google_measurement, "Google計測設定", "pass", "公開LPはGA4/GSC対象です。") if ENV["GA4_MEASUREMENT_ID"].present?

      check(:google_measurement, "Google計測設定", "warning", "公開LPは対象ですが、GA4_MEASUREMENT_IDが未設定です。")
    end

    def daily_run_check
      return check(:daily_run, "Daily Run対象", "fail", "Businessがありません。", repair_action: "create_business") unless business
      return check(:daily_run, "Daily Run対象", "pass", "Daily Run対象です。") if business.daily_run_enabled?

      check(:daily_run, "Daily Run対象", "fail", "daily_run_enabledがOFFです。", repair_action: "enable_daily_run")
    end

    def serp_check
      return check(:serp, "SERP対象", "fail", "Businessがありません。", repair_action: "create_business") unless business
      return check(:serp, "SERP対象", "fail", "serp_enabledがOFFです。", repair_action: "enable_serp") unless business.serp_enabled?
      serp_optional = Aicoo::Serp::OptionalMode.call
      return check(:serp, "SERP対象", "pass", "SERP対象でAPIキーも設定済みです。") if serp_optional.api_key_configured

      check(
        :missing_serp_key,
        "SERP対象",
        "warning",
        serp_optional.message,
        details: {
          source_key: "serp",
          reason: serp_optional.reason,
          skipped_steps: serp_optional.dependent_steps,
          continued_steps: serp_optional.independent_steps
        }
      )
    end

    def improvement_check
      return check(:improvement_generation, "改善提案生成", "fail", "Businessがありません。", repair_action: "create_business") unless business
      return check(:improvement_generation, "改善提案生成", "pass", "改善提案が生成済みです。") if business.action_candidates.exists?

      check(:improvement_generation, "改善提案生成", "warning", "改善提案はまだ生成されていません。Daily Run後に確認してください。")
    end

    def auto_revision_queue_check
      return check(:auto_revision_queue, "Auto Revision Queue", "fail", "Businessがありません。", repair_action: "create_business") unless business
      return check(:auto_revision_queue, "Auto Revision Queue", "pass", "自動改訂キューがあります。") if business.auto_revision_tasks.exists?

      check(:auto_revision_queue, "Auto Revision Queue", "warning", "Auto Revision Queueはまだ空です。")
    end

    def build_auto_revision_loop_checks
      [
        cron_daily_run_loop_check,
        analytics_loop_check,
        action_candidate_loop_check,
        auto_revision_queue_setting_loop_check,
        auto_revision_queue_run_loop_check,
        auto_revision_task_loop_check,
        codex_prompt_loop_check,
        owner_approval_loop_check,
        execution_result_loop_check,
        learning_loop_check
      ]
    end

    def cron_daily_run_loop_check
      run = latest_daily_run
      return check(:loop_daily_run, "Render Cron / Daily Run", "warning", "Daily Run履歴がありません。Cronまたは手動実行後に確認してください。", details: loop_path("/aicoo_daily_runs")) unless run

      details = loop_details(
        path: "/aicoo_daily_runs/#{run.id}",
        run_id: run.id,
        status: run.status,
        source: run.source,
        target_date: run.target_date
      )
      case run.status
      when "success"
        check(:loop_daily_run, "Render Cron / Daily Run", "pass", "最新Daily Run ##{run.id} は成功しています。", details:)
      when "running"
        check(:loop_daily_run, "Render Cron / Daily Run", "warning", "最新Daily Run ##{run.id} は実行中です。完了後にAutoRevision Queueが評価されます。", details:)
      when "partial_failed"
        check(:loop_daily_run, "Render Cron / Daily Run", "warning", "最新Daily Run ##{run.id} はpartial_failedです。AutoRevision Queueは成功Run後だけ実行されます。", details:)
      else
        check(:loop_daily_run, "Render Cron / Daily Run", "fail", "最新Daily Run ##{run.id} が#{run.status}です。AutoRevision Queueへ進めません。", details:)
      end
    end

    def analytics_loop_check
      step = latest_daily_run_step("analytics_fetch")
      return check(:loop_analytics, "GA4/GSC取得", "warning", "最新Daily Runにanalytics_fetch stepがありません。", details: loop_path("/aicoo_daily_runs")) unless step

      details = step_loop_details(step)
      return check(:loop_analytics, "GA4/GSC取得", "pass", "analytics_fetchは成功しています。", details:) if step.status == "success"

      status = step.status == "skipped" ? "warning" : "fail"
      message = step.metadata.to_h["message"].presence || step.error_message.presence || "analytics_fetchが#{step.status}です。"
      check(:loop_analytics, "GA4/GSC取得", status, message, details:)
    end

    def action_candidate_loop_check
      candidate_count = scoped_action_candidates.count
      run = latest_daily_run
      details = loop_details(
        path: "/action_candidates",
        candidate_count:,
        latest_run_generated_count: run&.action_candidates_generated_count
      )
      return check(:loop_action_candidate, "ActionCandidate生成", "pass", "#{candidate_count}件の改善候補があります。", details:) if candidate_count.positive?

      step = latest_daily_run_step("action_generation")
      message = step&.metadata.to_h["message"].presence ||
                "ActionCandidateがまだありません。Daily Runのaction_generation理由を確認してください。"
      check(:loop_action_candidate, "ActionCandidate生成", "warning", message, details: details.merge(step_metadata: step&.metadata.to_h))
    end

    def auto_revision_queue_setting_loop_check
      setting = AicooAutoRevisionSetting.current
      details = loop_details(
        path: "/admin/aicoo_auto_revision_settings",
        enabled: setting.enabled?,
        max_tasks_per_run: setting.max_tasks_per_run,
        minimum_final_score: setting.minimum_final_score.to_s,
        allow_medium_risk: setting.allow_medium_risk
      )
      return check(:loop_auto_revision_setting, "AutoRevision Queue設定", "pass", "AutoRevision QueueはONです。自動merge/deployとは別で、安全にタスク生成だけ行います。", details:) if setting.enabled?

      check(:loop_auto_revision_setting, "AutoRevision Queue設定", "warning", "AutoRevision QueueがOFFです。Daily Run後にAutoRevisionTaskは自動生成されません。", details:)
    end

    def auto_revision_queue_run_loop_check
      queue_run = latest_queue_run
      details = loop_details(
        path: "/auto_revision_tasks/codex_queue",
        latest_queue_run_id: queue_run&.id,
        latest_daily_run_id: latest_daily_run&.id,
        latest_daily_run_status: latest_daily_run&.status
      )
      return check(:loop_auto_revision_queue_run, "AutoRevisionTask生成", "warning", "AutoRevision Queueの実行履歴がありません。Queue設定と最新Daily Run statusを確認してください。", details:) unless queue_run

      queue_message = queue_run.metadata.to_h["message"].presence
      details = details.merge(
        generated_tasks_count: queue_run.generated_tasks_count,
        skipped_candidates_count: queue_run.skipped_candidates_count,
        high_risk_candidates_count: queue_run.high_risk_candidates_count,
        reason: queue_run.metadata.to_h["reason"],
        skipped_reasons: queue_run.metadata.to_h["skipped_reasons"]
      )
      if queue_run.generated_tasks_count.to_i.positive?
        check(:loop_auto_revision_queue_run, "AutoRevisionTask生成", "pass", "AutoRevisionTaskを#{queue_run.generated_tasks_count}件生成しました。", details:)
      else
        check(:loop_auto_revision_queue_run, "AutoRevisionTask生成", "warning", queue_message.presence || "AutoRevision Queueは実行されましたが生成0件です。", details:)
      end
    end

    def auto_revision_task_loop_check
      count = scoped_auto_revision_tasks.count
      details = loop_details(path: "/auto_revision_tasks", auto_revision_task_count: count)
      return check(:loop_auto_revision_task, "改修タスク保存", "pass", "#{count}件のAutoRevisionTaskがあります。", details:) if count.positive?

      check(:loop_auto_revision_task, "改修タスク保存", "warning", "AutoRevisionTaskがまだありません。ActionCandidateにexecution_promptがあるか、Queue設定を確認してください。", details:)
    end

    def codex_prompt_loop_check
      task = scoped_auto_revision_tasks.by_priority.first
      return check(:loop_codex_prompt, "Codex Prompt生成", "warning", "AutoRevisionTaskがないためCodex Promptを確認できません。", details: loop_path("/auto_revision_tasks")) unless task

      prompt_ready = task.codex_prompt_markdown.present?
      details = loop_details(path: "/auto_revision_tasks/#{task.id}/export_codex_prompt", task_id: task.id, status: task.status, risk_level: task.risk_level)
      return check(:loop_codex_prompt, "Codex Prompt生成", "pass", "AutoRevisionTask ##{task.id} のCodex Promptを表示できます。", details:) if prompt_ready

      check(:loop_codex_prompt, "Codex Prompt生成", "fail", "AutoRevisionTask ##{task.id} のCodex Promptが空です。", details:)
    end

    def owner_approval_loop_check
      waiting_count = scoped_auto_revision_tasks.where(status: "waiting_approval").count
      draft_count = scoped_auto_revision_tasks.where(status: "draft").count
      ready_count = scoped_auto_revision_tasks.where(status: %w[approved ready_for_codex queued sent_to_codex running]).count
      details = loop_details(
        path: "/owner/focus",
        waiting_approval_count: waiting_count,
        draft_count:,
        ready_or_running_count: ready_count,
        auto_revision_mode: business&.auto_revision_mode
      )
      return check(:loop_owner_approval, "Owner承認待ち", "pass", "#{waiting_count}件がOwner承認待ちです。", details:) if waiting_count.positive?
      return check(:loop_owner_approval, "Owner承認待ち", "pass", "#{ready_count}件が承認後またはCodex投入準備中です。", details:) if ready_count.positive?
      return check(:loop_owner_approval, "Owner承認待ち", "warning", "AutoRevisionTaskはありますがdraftです。Businessのauto_revision_modeがmanualの場合、承認待ちではなく提案のみになります。", details:) if draft_count.positive?

      check(:loop_owner_approval, "Owner承認待ち", "warning", "Owner Homeに出せる改修タスクがまだありません。", details:)
    end

    def execution_result_loop_check
      result_count = scoped_action_results.count
      activity_count = scoped_business_activity_logs.count
      details = loop_details(
        path: "/action_results",
        action_result_count: result_count,
        business_activity_log_count: activity_count,
        activity_log_path: "/admin/business_activity_logs"
      )
      return check(:loop_execution_result, "実行後Activity / ActionResult", "pass", "ActionResultまたはActivity Logが記録されています。", details:) if result_count.positive? || activity_count.positive?

      check(:loop_execution_result, "実行後Activity / ActionResult", "warning", "実行結果はまだ未登録です。改修後はActionResultまたはActivity Logへ戻してください。", details:)
    end

    def learning_loop_check
      evaluation_count = safe_count(ActivityEvaluation, business_id: business&.id)
      snapshot_count = scoped_action_candidates.joins(:action_candidate_score_snapshots).distinct.count
      details = loop_details(
        path: "/admin/activity_learning_e2e_check",
        activity_evaluation_count: evaluation_count,
        score_snapshot_candidate_count: snapshot_count
      )
      return check(:loop_learning, "Learning", "pass", "評価またはScore Snapshotが学習データとして存在します。", details:) if evaluation_count.positive? || snapshot_count.positive?

      check(:loop_learning, "Learning", "warning", "実行結果評価またはScore Snapshotがまだありません。Daily RunのLearning系step後に確認してください。", details:)
    end

    def check(key, label, status, message, repair_action: nil, details: {})
      Check.new(key: key.to_s, label:, status:, message:, repair_action:, details:)
    end

    def idea_approved?
      return false unless idea_item

      idea_item.status.in?(%w[approved manually_approved owner_approved lp_generated published learning_evaluated mvp_spec_ready continuing improving]) ||
        idea_item.business_id.present? ||
        idea_item.aicoo_lab_landing_page&.publicly_visible?
    end

    def business_visible?
      Business.real_businesses.exists?(id: business.id)
    end

    def business_visibility_details
      {
        id: business.id,
        name: business.name,
        status: business.status,
        source: business.source,
        created_by_aicoo: business.created_by_aicoo?,
        launched: business.launched?,
        system_business: business.system_business?
      }
    end

    def repair_business!
      return business if business
      return Aicoo::IdeaPipeline::BusinessLinker.new(idea_item).call if idea_item

      create_business_from_landing_page!
    end

    def repair_landing_page_link!
      page = landing_page
      raise ArgumentError, "紐付けるLPがありません。" unless page

      target_business = business || repair_business!
      page.update!(business: target_business)
      idea_item&.update!(business: target_business, aicoo_lab_landing_page: page)
      target_business
    end

    def create_business_from_landing_page!
      page = landing_page
      raise ArgumentError, "Business化できる公開LPがありません。" unless page

      Business.create!(
        name: page.headline.presence || page.seo_title.presence || "公開LP ##{page.id}",
        description: page.subheadline.presence || page.seo_description.presence || page.body.to_s.truncate(160),
        category: "landing_page",
        status: "launched",
        source: "landing_page",
        created_by_aicoo: true,
        launched: true,
        daily_run_enabled: true,
        serp_enabled: true,
        auto_revision_mode: "manual",
        auto_deploy_mode: "manual"
      ).tap do |created_business|
        page.update!(business: created_business)
      end
    end

    def require_business!
      business || repair_business!
    end

    def clear_memoized_subjects
      @idea_item = nil
      @business = nil
      @landing_page = nil
    end

    def latest_daily_run
      @latest_daily_run ||= AicooDailyRun.order(target_date: :desc, created_at: :desc).first
    end

    def latest_daily_run_step(step_name)
      return unless latest_daily_run

      latest_daily_run.aicoo_daily_run_steps.where(step_name:).order(created_at: :desc).first
    end

    def latest_queue_run
      @latest_queue_run ||= AutoRevisionQueueRun.recent.first
    end

    def scoped_action_candidates
      scope = ActionCandidate.active_for_ranking
      business ? scope.where(business_id: business.id) : scope
    end

    def scoped_auto_revision_tasks
      scope = AutoRevisionTask.active
      business ? scope.where(business_id: business.id) : scope
    end

    def scoped_action_results
      scope = ActionResult.all
      business ? scope.where(business_id: business.id) : scope
    end

    def scoped_business_activity_logs
      scope = BusinessActivityLog.all
      business ? scope.where(business_id: business.id) : scope
    end

    def step_loop_details(step)
      loop_details(
        path: "/aicoo_daily_runs/#{step.aicoo_daily_run_id}",
        step_id: step.id,
        step_status: step.status,
        error_message: step.error_message,
        metadata: step.metadata.to_h
      )
    end

    def loop_path(path)
      loop_details(path:)
    end

    def loop_details(**details)
      details.compact
    end

    def safe_count(model, conditions)
      return 0 if model.blank? || conditions.values.any?(&:blank?)

      model.where(conditions).count
    rescue StandardError
      0
    end
  end
end
