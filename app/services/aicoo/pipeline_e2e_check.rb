module Aicoo
  class PipelineE2eCheck
    Check = Data.define(:key, :label, :status, :message, :repair_action, :details)
    Result = Data.define(:pipeline_run, :idea_item, :business, :landing_page, :checks, :generated_at) do
      def overall_status
        return "fail" if checks.any? { |check| check.status == "fail" }
        return "warning" if checks.any? { |check| check.status == "warning" }

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
  end
end
