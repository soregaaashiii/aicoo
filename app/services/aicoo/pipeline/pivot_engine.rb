module Aicoo
  module Pipeline
    class PivotEngine
      def initialize(subject)
        @subject = subject
      end

      def call
        decision = decision_for_subject
        {
          "decision" => decision,
          "reason" => reason_for(decision),
          "ctr" => metric("ctr"),
          "cv_rate" => conversion_rate,
          "expected_value_yen" => expected_value_yen.to_s
        }
      end

      private

      attr_reader :subject

      def decision_for_subject
        return subject.mvp_decision if subject.is_a?(IdeaPipelineItem) && subject.mvp_decision.present?
        return "continue" if conversion_rate >= 0.02
        return "pivot" if expected_value_yen.positive? && conversion_rate < 0.005

        "continue"
      end

      def reason_for(decision)
        {
          "develop" => "MVP開発候補です。",
          "continue_lp" => "LP検証を継続します。",
          "improve" => "LP改善を優先します。",
          "end" => "終了候補です。",
          "pivot" => "反応が弱いためPivot候補です。",
          "continue" => "継続候補です。"
        }.fetch(decision, "継続候補です。")
      end

      def landing_page
        @landing_page ||= if subject.is_a?(IdeaPipelineItem)
          subject.aicoo_lab_landing_page
        elsif subject.is_a?(Business)
          subject.aicoo_lab_landing_pages.publicly_available.order(updated_at: :desc).first
        end
      end

      def conversion_rate
        return 0.to_d unless landing_page

        landing_page.signup_rate.to_d
      end

      def metric(key)
        subject.respond_to?(:learning_snapshot) ? subject.learning_snapshot.to_h[key].to_d : 0.to_d
      end

      def expected_value_yen
        if subject.respond_to?(:expected_profit_yen)
          subject.expected_profit_yen.to_d
        elsif subject.is_a?(Business)
          subject.current_month_profit.to_d
        else
          0.to_d
        end
      end
    end
  end
end
