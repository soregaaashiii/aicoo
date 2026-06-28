module Aicoo
  module IdeaPipeline
    class MvpSpecBuilder
      def initialize(item)
        @item = item
      end

      def call
        decision = decision_for_item
        item.update!(
          status: decision == "develop" ? "mvp_spec_ready" : status_for(decision),
          current_stage: "mvp",
          mvp_decision: decision,
          mvp_specification: decision == "develop" ? specification : item.mvp_specification,
          mvp_decided_at: Time.current,
          metadata: item.metadata.to_h.merge(
            "mvp_decision" => decision,
            "mvp_decided_at" => Time.current.iso8601
          )
        )
        item
      end

      private

      attr_reader :item

      def decision_for_item
        recommendation = item.learning_snapshot.to_h["recommendation"]
        return recommendation if IdeaPipelineItem::MVP_DECISIONS.include?(recommendation)
        return "develop" if item.final_score.to_d >= 80
        return "continue_lp" if item.final_score.to_d >= 65
        return "improve" if item.final_score.to_d >= 45

        "end"
      end

      def status_for(decision)
        {
          "continue_lp" => "continuing",
          "improve" => "improving",
          "end" => "ended"
        }.fetch(decision, "ended")
      end

      def specification
        <<~SPEC.strip
          # #{item.title} MVP仕様書

          ## 目的
          #{item.short_description}

          ## 解決課題
          #{item.problem}

          ## 想定ユーザー
          #{item.target_user}

          ## 収益モデル
          #{item.revenue_model}

          ## MVP範囲
          #{item.mvp_concept}

          ## 画面一覧
          - 公開LP
          - 事前登録/問い合わせフォーム
          - 管理用リード一覧
          - 反応計測ダッシュボード

          ## DB案
          - leads: email, name, source, landing_page_id, created_at
          - mvp_events: event_type, metadata, occurred_at
          - mvp_feedbacks: lead_id, score, comment

          ## API案
          - POST /leads
          - POST /mvp_events
          - GET /admin/mvp/leads

          ## Codexへ渡すTODO
          - 既存公開LP基盤を壊さず、フォーム送信とイベント記録を追加する
          - DB migrationを最小化する
          - GA4/GSC/robots/sitemapの既存挙動を維持する
          - db:drop / db:reset / drop database は実行しない

          ## 確認コマンド
          - bin/rails test
          - bin/rails zeitwerk:check
          - RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rubocop
        SPEC
      end
    end
  end
end
