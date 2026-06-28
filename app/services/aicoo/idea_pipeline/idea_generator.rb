module Aicoo
  module IdeaPipeline
    class IdeaGenerator
      DEFAULT_IDEAS = [
        {
          title: "地域特化の予約前チェックリストLP",
          short_description: "地域名と用途を入れるだけで、比較前に見るべき条件を整理するLP。",
          problem: "検索者は候補が多すぎて、問い合わせ前に何を確認すべきか分かりにくい。",
          target_user: "地域名とサービス名で検索している比較検討ユーザー",
          revenue_model: "送客、問い合わせ、アフィリエイト、月額掲載",
          mvp_concept: "1カテゴリ1地域でチェックリストLPを公開し、CTA反応を見る。",
          lp_concept: "失敗しない選び方、比較軸、問い合わせ前チェック、CTAを1ページにまとめる。",
          difficulty_score: 35,
          development_hours: 8,
          ai_implementation_score: 80
        },
        {
          title: "ニッチ業務のAI診断LP",
          short_description: "入力内容から改善余地を診断し、相談や資料請求につなげる。",
          problem: "専門業務は課題が見えにくく、導入前に費用対効果を判断しづらい。",
          target_user: "業務改善を考えている小規模事業者",
          revenue_model: "診断後のリード獲得、制作代行、SaaS月額",
          mvp_concept: "フォーム診断と結果メールだけで需要を検証する。",
          lp_concept: "課題診断、改善例、導入ステップ、無料診断CTA。",
          difficulty_score: 50,
          development_hours: 16,
          ai_implementation_score: 70
        },
        {
          title: "検索需要のあるテンプレート配布LP",
          short_description: "探されている業務テンプレートを配布し、利用者を集める。",
          problem: "実務者はすぐ使える雛形を探しているが、業界別に最適化されたものが少ない。",
          target_user: "業務テンプレートを検索する担当者",
          revenue_model: "メール獲得、広告、上位版販売、関連SaaS誘導",
          mvp_concept: "テンプレート1種類をLPで配布し、DL率を測る。",
          lp_concept: "無料テンプレート、使い方、注意点、有料版CTA。",
          difficulty_score: 25,
          development_hours: 5,
          ai_implementation_score: 90
        }
      ].freeze

      Result = Data.define(:created_count, :items)

      def self.call(count: 3)
        new(count:).call
      end

      def initialize(count: 3)
        @count = count.to_i.positive? ? count.to_i : 3
      end

      def call
        items = DEFAULT_IDEAS.first(count).map { |attributes| create_item(attributes) }
        Result.new(created_count: items.size, items:)
      end

      private

      attr_reader :count

      def create_item(attributes)
        IdeaPipelineItem.create!(
          attributes.merge(
            status: "idea",
            current_stage: "idea",
            metadata: {
              "generated_by" => "Aicoo::IdeaPipeline::IdeaGenerator",
              "generated_at" => Time.current.iso8601
            }
          )
        )
      end
    end
  end
end
