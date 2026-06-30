module Aicoo
  class MvpReadyCheck
    Check = Data.define(:key, :label, :passed, :message)
    Result = Data.define(:checks) do
      def ready?
        checks.all?(&:passed)
      end

      def warnings
        checks.reject(&:passed)
      end
    end

    def initialize(business, lp_summaries = nil)
      @business = business
      @lp_summaries = lp_summaries || Aicoo::LpEvaluationSummary.for_business(business)
    end

    def call
      Result.new(checks: [
        published_lp_check,
        measurement_check,
        conversion_check,
        target_check,
        price_check,
        repository_check,
        deploy_target_check
      ])
    end

    private

    attr_reader :business, :lp_summaries

    def published_landing_pages
      @published_landing_pages ||= business.aicoo_lab_landing_pages.publicly_available
    end

    def best_summary
      @best_summary ||= lp_summaries.max_by { |summary| [ Aicoo::LpEvaluationSummary.verdict_rank(summary.verdict), summary.cv, summary.cta_clicks, summary.pv ] }
    end

    def published_lp_check
      passed = published_landing_pages.exists?
      Check.new(:published_lp, "LPが公開済み", passed, passed ? "公開LPがあります。" : "公開LPがありません。")
    end

    def measurement_check
      passed = lp_summaries.any? { |summary| summary.pv.positive? || summary.gsc_clicks.positive? || summary.gsc_impressions.positive? }
      Check.new(:measurement, "計測がある", passed, passed ? "PVまたはGSC計測があります。" : "PV/GSC計測がまだありません。")
    end

    def conversion_check
      passed = lp_summaries.any? { |summary| summary.cv.positive? || summary.cta_clicks.positive? }
      Check.new(:conversion, "CVまたはCTAクリックがある", passed, passed ? "CVまたはCTAクリックがあります。" : "CV/CTAクリックがまだありません。")
    end

    def target_check
      text = [ business.description, best_summary&.landing_page&.public_subheadline, best_summary&.landing_page&.public_body ].join(" ")
      passed = text.length >= 20
      Check.new(:target, "ターゲットが明確", passed, passed ? "LP/Business説明から対象ユーザーを読み取れます。" : "対象ユーザーの説明を補ってください。")
    end

    def price_check
      passed = business.aicoo_lab_landing_pages.where.not(assumed_price_yen: nil).exists?
      Check.new(:price, "価格仮説がある", passed, passed ? "LPに価格仮説があります。" : "初期価格案を設定してください。")
    end

    def repository_check
      passed = business.aicoo_internal_codex? || business.codex_repository_name.present?
      Check.new(:repository, "repositoryが設定されている", passed, passed ? "Codex実行先があります。" : "外部Repositoryを設定してください。")
    end

    def deploy_target_check
      profile = business.business_execution_profile
      service_has_deploy_target = business.business_services.where.not(deploy_target: [ nil, "" ]).exists?
      passed = business.aicoo_internal_codex? || profile&.deploy_command.present? || service_has_deploy_target
      Check.new(:deploy_target, "deploy先が設定されている", passed, passed ? "Deploy先またはAICOO内部対象があります。" : "deploy_commandまたはDeploy先を設定してください。")
    end
  end
end
