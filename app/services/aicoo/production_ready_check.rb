module Aicoo
  class ProductionReadyCheck
    Check = Data.define(:key, :label, :passed, :message)
    Result = Data.define(:checks) do
      def ready?
        checks.all?(&:passed)
      end

      def warnings
        checks.reject(&:passed)
      end
    end

    def initialize(business, mvp_summaries = nil)
      @business = business
      @mvp_summaries = mvp_summaries || Aicoo::MvpEvaluationSummary.for_business(business)
    end

    def call
      Result.new(checks: [
        service_url_check,
        repository_check,
        deploy_target_check,
        stripe_check,
        measurement_check,
        registration_check,
        price_check,
        feedback_check
      ])
    end

    private

    attr_reader :business, :mvp_summaries

    def services
      business.business_services
    end

    def service_url_check
      passed = services.where.not(url: [ nil, "" ]).or(services.where.not(domain: [ nil, "" ])).exists?
      Check.new(:service_url, "サービスURLがある", passed, passed ? "サービスURLまたはドメインがあります。" : "サービスURLを設定してください。")
    end

    def repository_check
      passed = business.aicoo_internal_codex? || business.codex_repository_name.present? || services.where.not(repository: [ nil, "" ]).exists?
      Check.new(:repository, "repositoryが設定されている", passed, passed ? "Repository設定があります。" : "Repositoryを設定してください。")
    end

    def deploy_target_check
      profile = business.business_execution_profile
      passed = business.aicoo_internal_codex? || profile&.deploy_command.present? || services.where.not(deploy_target: [ nil, "" ]).exists?
      Check.new(:deploy_target, "deploy先が設定されている", passed, passed ? "Deploy先があります。" : "Deploy先を設定してください。")
    end

    def stripe_check
      passed = services.where.not(stripe_account: [ nil, "" ]).exists?
      Check.new(:stripe, "Stripe設定がある", passed, passed ? "Stripe設定があります。" : "Stripeまたは課金導線を設定してください。")
    end

    def measurement_check
      passed = mvp_summaries.any? { |summary| summary.active_users.positive? || summary.registrations.positive? }
      Check.new(:measurement, "計測がある", passed, passed ? "利用または登録計測があります。" : "MVP利用計測がまだありません。")
    end

    def registration_check
      passed = mvp_summaries.any? { |summary| summary.registrations.positive? }
      Check.new(:registration, "登録または問い合わせがある", passed, passed ? "登録または問い合わせがあります。" : "登録/問い合わせがまだありません。")
    end

    def price_check
      passed = business.aicoo_lab_landing_pages.where.not(assumed_price_yen: nil).exists? ||
               services.any? { |service| service.metadata.to_h["price_hypothesis"].present? }
      Check.new(:price, "価格仮説がある", passed, passed ? "価格仮説があります。" : "本番前に価格仮説を設定してください。")
    end

    def feedback_check
      passed = services.any? { |service| service.metadata.to_h["user_feedback"].present? } ||
               business.business_activity_logs.where(activity_type: "user_feedback_received").exists?
      Check.new(:feedback, "利用者フィードバックがある", passed, passed ? "利用者フィードバックがあります。" : "利用者フィードバックを記録してください。")
    end
  end
end
