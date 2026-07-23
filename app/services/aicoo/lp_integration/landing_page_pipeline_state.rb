module Aicoo
  module LpIntegration
    module LandingPagePipelineState
      STAGES = [
        [ "prompt_pending", "Prompt生成待ち" ],
        [ "lovable_pending", "Lovable待ち" ],
        [ "github_pending", "GitHub待ち" ],
        [ "cloudflare_pending", "Cloudflare待ち" ],
        [ "publication_check_pending", "公開確認待ち" ],
        [ "ga4_pending", "GA4待ち" ],
        [ "gsc_pending", "GSC待ち" ],
        [ "improvement_pending", "改善待ち" ],
        [ "completed", "完了" ]
      ].freeze

      module_function

      def build(current:, approval_required: true)
        current_index = STAGES.index { |key, _label| key == current.to_s } || 0
        STAGES.each_with_index.map do |(key, label), index|
          status = if index < current_index
            "completed"
          elsif index == current_index
            approval_required ? "waiting_approval" : "pending"
          else
            "blocked"
          end
          { "key" => key, "label" => label, "status" => status }
        end
      end
    end
  end
end
