module Aicoo
  class CodexPromptComposer
    def self.call(business:, request_body:)
      new(business:, request_body:).call
    end

    def initialize(business:, request_body:)
      @business = business
      @request_body = request_body.to_s.strip
    end

    def call
      CodexPromptRule.ensure_defaults!

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

    attr_reader :business, :request_body

    def global_rules_text
      rules = CodexPromptRule.global_rules.active.ordered
      return "有効な共通ルールはありません。" if rules.empty?

      rules.map(&:content).join("\n\n")
    end

    def service_rules_text
      return "Business未選択のため、サービス固有ルールはありません。" unless business

      rules = CodexPromptRule.service_rules.active.where(business:).ordered
      return "#{business.name} の有効なサービス固有ルールはありません。" if rules.empty?

      rules.map(&:content).join("\n\n")
    end
  end
end
