module Aicoo
  class CodexPromptComposer
    def self.call(business:, request_body:, rules: nil)
      new(business:, request_body:, rules:).call
    end

    def initialize(business:, request_body:, rules: nil)
      @business = business
      @request_body = request_body.to_s.strip
      @rules = rules
    end

    def call
      CodexPromptRule.ensure_defaults! unless rules

      <<~PROMPT.strip
        【共通ルール】
        #{global_rules_text}

        【サービス固有ルール】
        #{service_rules_text}

        【今回の依頼】
        #{request_body.presence || "今回の依頼本文が未入力です。"}
      PROMPT
    end

    private

    attr_reader :business, :request_body, :rules

    def global_rules_text
      rows = rules ? rules.select { |rule| rule.scope == "global" } : CodexPromptRule.global_rules.active.ordered
      return "有効な共通ルールはありません。" if rows.empty?

      rows.map(&:content).join("\n\n")
    end

    def service_rules_text
      return "Business未選択のため、サービス固有ルールはありません。" unless business

      rows = if rules
        rules.select { |rule| rule.scope == "service" && rule.business_id == business.id }
      else
        CodexPromptRule.service_rules.active.where(business:).ordered
      end
      return "#{business.name} の有効なサービス固有ルールはありません。" if rows.empty?

      rows.map(&:content).join("\n\n")
    end
  end
end
