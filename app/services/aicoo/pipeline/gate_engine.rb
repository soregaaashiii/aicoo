module Aicoo
  module Pipeline
    class GateEngine
      SERP_SCORE_THRESHOLD = 60

      def initialize(subject)
        @subject = subject
      end

      def call
        {
          "serp" => serp_gate,
          "lp" => lp_gate,
          "publish" => publish_gate,
          "measure" => measure_gate,
          "improve" => improve_gate,
          "deploy" => deploy_gate,
          "learning" => learning_gate
        }
      end

      private

      attr_reader :subject

      def idea_item
        subject if subject.is_a?(IdeaPipelineItem)
      end

      def business
        idea_item&.business || subject if subject.is_a?(Business)
      end

      def landing_page
        idea_item&.aicoo_lab_landing_page || business&.aicoo_lab_landing_pages&.order(updated_at: :desc)&.first
      end

      def serp_gate
        score = idea_item&.final_score.to_d
        return gate("pending", "score_pending", "Score後にSERP判定します。") if score.zero? && idea_item&.final_score.blank?
        return gate("skipped", "score_below_serp_threshold", "scoreが閾値未満のためSERPは任意スキップです。") if score < SERP_SCORE_THRESHOLD

        gate("open", "score_passed", "scoreが閾値以上のためSERP実行できます。")
      end

      def lp_gate
        return gate("blocked", "lp_blocked", "LP生成停止状態です。") if idea_item&.lp_generation_blocked?
        return gate("open", "owner_or_score_allows_lp", "SERPなしでもLP生成できます。") if idea_item&.lp_generation_allowed?

        gate("waiting", "owner_approval_required", "Owner承認待ちです。")
      end

      def publish_gate
        return gate("done", "published", "公開済みです。") if landing_page&.publicly_visible?
        return gate("open", "lp_generated", "LP生成済みのため公開できます。") if landing_page

        gate("waiting", "lp_required", "LP生成待ちです。")
      end

      def measure_gate
        return gate("waiting", "publish_required", "公開後に計測します。") unless landing_page&.publicly_visible?
        return gate("open", "sample_ready", "30日経過または十分なPVで計測します。") if sample_ready?

        gate("waiting", "sample_waiting", "30日または1000PVまで待機します。")
      end

      def improve_gate
        mode = business&.auto_revision_mode.presence || "manual"
        return gate("waiting", "manual_mode", "手動モードのため提案で停止します。") if mode == "manual"
        return gate("approval", "approval_mode", "承認後に改訂へ進みます。") if mode == "approval"

        gate("open", "automatic_low_risk_only", "低リスクのみ自動改訂候補へ進みます。")
      end

      def deploy_gate
        return gate("approval", "deploy_requires_approval", "初期段階ではDeployは承認制です。") if business&.automatic_auto_revision?

        gate("waiting", "deploy_not_required", "Deploy待ちではありません。")
      end

      def learning_gate
        return gate("open", "result_ready", "結果を学習へ反映できます。") if idea_item&.learning_evaluated_at.present?

        gate("waiting", "measure_required", "Measure後に学習します。")
      end

      def sample_ready?
        return false unless landing_page

        published_at = landing_page.published_at
        return true if published_at && published_at <= 30.days.ago

        landing_page.view_count >= 1_000
      end

      def gate(status, reason, message)
        {
          "status" => status,
          "reason" => reason,
          "message" => message
        }
      end
    end
  end
end
