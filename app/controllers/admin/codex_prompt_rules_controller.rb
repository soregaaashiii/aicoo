module Admin
  class CodexPromptRulesController < ApplicationController
    before_action :ensure_defaults
    before_action :set_rule, only: %i[edit update toggle]

    def index
      @global_rules = CodexPromptRule.global_rules.ordered
      @service_rules = CodexPromptRule.service_rules.includes(:business).ordered
    end

    def edit
    end

    def update
      if @rule.update(rule_params)
        redirect_to admin_codex_prompt_rules_path, notice: "Codex Prompt Ruleを保存しました。"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def toggle
      @rule.update!(active: !@rule.active?)
      redirect_to admin_codex_prompt_rules_path, notice: "Codex Prompt Ruleの有効状態を切り替えました。"
    end

    def preview
      @businesses = Business.real_businesses.order(:name)
      @business = @businesses.find { |business| business.id.to_s == params[:business_id].to_s }
      @request_body = params[:request_body].presence || default_request_body
      @preview_prompt = Aicoo::CodexPromptComposer.call(business: @business, request_body: @request_body)
    end

    private

    def ensure_defaults
      CodexPromptRule.ensure_defaults!
    end

    def set_rule
      @rule = CodexPromptRule.find(params.expect(:id))
    end

    def rule_params
      params.expect(codex_prompt_rule: %i[name rule_category content active priority])
    end

    def default_request_body
      <<~TEXT.strip
        目的:
        対象サービスの改善を実装してください。

        確認:
        変更ファイル一覧と使い方を最後にまとめてください。
      TEXT
    end
  end
end
