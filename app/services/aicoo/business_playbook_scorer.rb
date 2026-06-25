module Aicoo
  class BusinessPlaybookScorer
    Result = Data.define(:score, :confidence, :coefficient, :reason, :metadata)

    MIN_CONFIDENCE_FOR_FULL_EFFECT = 40.to_d

    def initialize(subject)
      @subject = subject
    end

    def call
      return neutral_result("Business未設定のため汎用ルールを使います。") unless business
      return neutral_result("Business Playbook未学習のため汎用ルールを使います。") unless playbook&.learned?

      row = playbook_row
      return neutral_result("同種データ不足のため汎用ルールを使います。") unless row

      score = row["score"].to_d
      confidence = playbook.confidence_score.to_d
      raw_coefficient = 1 + ((score - 50) / 100 * 0.18)
      softened = 1 + ((raw_coefficient - 1) * effect_ratio(confidence))
      coefficient = clamp(softened, 0.92.to_d, 1.12.to_d)

      Result.new(
        score:,
        confidence:,
        coefficient:,
        reason: "Business Playbook上、#{row['type']} のscoreは#{score.round(1)} / confidence #{confidence.round(1)}です。",
        metadata: {
          "score" => score.to_s,
          "confidence" => confidence.to_s,
          "coefficient" => coefficient.to_s,
          "row" => row,
          "reason" => "Business Playbook上、#{row['type']} のscoreは#{score.round(1)} / confidence #{confidence.round(1)}です。"
        }
      )
    end

    private

    attr_reader :subject

    def neutral_result(reason)
      Result.new(
        score: 50.to_d,
        confidence: 0.to_d,
        coefficient: 1.to_d,
        reason:,
        metadata: {
          "score" => "50.0",
          "confidence" => "0.0",
          "coefficient" => "1.0",
          "reason" => reason
        }
      )
    end

    def playbook_row
      if subject.respond_to?(:action_type)
        playbook.action_type_summary.to_h[subject.action_type]
      elsif subject.respond_to?(:opportunity_type)
        playbook.opportunity_type_summary.to_h[subject.opportunity_type]
      end
    end

    def business
      return subject.business if subject.respond_to?(:business) && subject.business

      nil
    end

    def playbook
      @playbook ||= business&.business_playbook
    end

    def effect_ratio(confidence)
      [ confidence / MIN_CONFIDENCE_FOR_FULL_EFFECT, 1.to_d ].min
    end

    def clamp(value, min, max)
      [ [ value.to_d, min ].max, max ].min.round(4)
    end
  end
end
