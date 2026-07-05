module Aicoo
  module BusinessAnalyzers
    class BaseAnalyzer
      Issue = Data.define(
        :key,
        :title,
        :description,
        :action_type,
        :quantity,
        :unit,
        :why,
        :expected_effect,
        :expected_value_yen,
        :success_probability,
        :strategic_value_score,
        :risk_reduction_score,
        :expected_hours,
        :confidence_score,
        :metadata
      )

      def self.call(...)
        new(...).call
      end

      def initialize(business:, today: Date.current)
        @business = business
        @today = today.to_date
        @skipped = []
      end

      def call
        return empty_result(handled: false) unless handled_business_type?

        detected_issues = issues.compact
        created = detected_issues.filter_map { |issue| create_candidate(issue) }
        duplicate_count = detected_issues.size - created.size
        duplicate_count.times { skipped << "直近7日以内に同じAnalyzer課題があるため作成しませんでした" }

        Result.new(
          business:,
          analyzer: self.class.name,
          created:,
          skipped:,
          issues: detected_issues,
          handled: true
        )
      end

      private

      attr_reader :business, :today, :skipped

      def handled_business_type?
        false
      end

      def issues
        []
      end

      def create_candidate(issue)
        if recent_duplicate?(issue)
          skipped << "#{issue.key}: duplicate"
          return
        end

        candidate = business.action_candidates.create!(
          title: issue.title,
          description: issue.description,
          action_type: issue.action_type,
          immediate_value_yen: issue.expected_value_yen,
          success_probability: issue.success_probability,
          strategic_value_score: issue.strategic_value_score,
          risk_reduction_score: issue.risk_reduction_score,
          confidence_score: issue.confidence_score,
          data_confidence_score: issue.confidence_score,
          expected_hours: issue.expected_hours,
          cost_yen: 0,
          status: "idea",
          generation_source: "business_analyzer",
          metadata: candidate_metadata(issue),
          evaluation_reason: evaluation_reason(issue),
          execution_prompt: execution_prompt(issue)
        )
        Aicoo::ActionCandidateInstructionStabilizer.call(candidate)
        candidate.reload
      end

      def candidate_metadata(issue)
        issue.metadata.to_h.deep_stringify_keys.merge(
          "source" => "business_analyzer",
          "analyzer" => self.class.name,
          "business_type" => business.business_type,
          "issue_key" => issue.key,
          "issue_quantity" => issue.quantity,
          "issue_unit" => issue.unit,
          "issue_why" => issue.why,
          "expected_effect" => issue.expected_effect,
          "expected_minutes" => (issue.expected_hours.to_d * 60).round,
          "business_type_playbook" => business.business_type_playbook.call(
            title: issue.title,
            description: issue.description,
            action_type: issue.action_type,
            evaluation_reason: issue.why,
            execution_prompt: issue.expected_effect
          ).metadata
        )
      end

      def evaluation_reason(issue)
        [
          "business_analyzer:#{issue.key}",
          "何を: #{issue.title}",
          "どれだけ: #{issue.quantity}#{issue.unit}",
          "なぜ: #{issue.why}",
          "期待効果: #{issue.expected_effect}"
        ].join("\n")
      end

      def execution_prompt(issue)
        <<~PROMPT.strip
          Analyzerが検出した課題に対して、実行方法だけを具体化してください。

          何を:
          #{issue.title}

          どれだけ:
          #{issue.quantity}#{issue.unit}

          なぜ:
          #{issue.why}

          期待効果:
          #{issue.expected_effect}

          注意:
          課題の再発見や一般論の提案はしないでください。上記の課題を実行する手順、変更対象、完成条件だけを書いてください。
        PROMPT
      end

      def recent_duplicate?(issue)
        business.action_candidates
                .where(created_at: duplicate_window_start..)
                .where(
                  "title = ? OR evaluation_reason LIKE ?",
                  issue.title,
                  "%business_analyzer:#{ActiveRecord::Base.sanitize_sql_like(issue.key)}%"
                )
                .exists?
      end

      def duplicate_window_start
        today.beginning_of_day - 7.days
      end

      def empty_result(handled:)
        Result.new(
          business:,
          analyzer: self.class.name,
          created: [],
          skipped: [],
          issues: [],
          handled:
        )
      end

      def yen(value)
        value.to_i
      end
    end
  end
end
