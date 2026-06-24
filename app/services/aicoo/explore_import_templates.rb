module Aicoo
  class ExploreImportTemplates
    Template = Data.define(:source_type, :title, :recommended_format, :csv_example, :text_example, :score_guide, :notes)

    CSV_HEADER = "title,description,score,observation_type"

    TEMPLATES = {
      "google_trends" => Template.new(
        source_type: "google_trends",
        title: "Google Trends",
        recommended_format: "csv",
        csv_example: <<~CSV.strip,
          title,description,score,observation_type
          シーシャ 大阪,検索需要が上昇傾向,85,trend
          電子タバコ カフェ,関連需要が増加,75,trend
        CSV
        text_example: "シーシャ 大阪\n電子タバコ カフェ",
        score_guide: [
          "90以上: 急上昇かつ事業と強く関連",
          "70〜89: 上昇傾向あり",
          "50〜69: 様子見",
          "49以下: 弱い"
        ],
        notes: [ "検索語そのものをtitleにし、なぜ伸びているかをdescriptionに入れてください。" ]
      ),
      "reddit" => Template.new(
        source_type: "reddit",
        title: "Reddit",
        recommended_format: "csv",
        csv_example: <<~CSV.strip,
          title,description,score,observation_type
          大阪で喫煙できる店が探しにくい,複数投稿で同様の不満,80,discussion
        CSV
        text_example: "大阪で喫煙できる店が探しにくい",
        score_guide: [
          "不満が明確なら高め",
          "繰り返し出ている話題なら加点",
          "既存事業に転用できるなら加点"
        ],
        notes: [ "投稿URLやsubreddit名はdescriptionへ短く残すと後で追いやすくなります。" ]
      ),
      "youtube" => Template.new(
        source_type: "youtube",
        title: "YouTube",
        recommended_format: "csv",
        csv_example: <<~CSV.strip,
          title,description,score,observation_type
          シーシャ初心者向け動画が伸びている,関連動画の再生数増加,75,trend
        CSV
        text_example: "シーシャ初心者向け動画が伸びている",
        score_guide: [
          "再生数やコメントが伸びているなら加点",
          "既存記事やLPに展開しやすいなら加点"
        ],
        notes: [ "動画タイトルだけでなく、伸びている理由をdescriptionに入れてください。" ]
      ),
      "x" => Template.new(
        source_type: "x",
        title: "X",
        recommended_format: "csv",
        csv_example: <<~CSV.strip,
          title,description,score,observation_type
          梅田 喫煙所 投稿増加,直近で同種投稿が複数,70,discussion
        CSV
        text_example: "梅田 喫煙所 投稿増加",
        score_guide: [
          "直近で複数投稿があるなら加点",
          "不満・探している・困っている投稿は高め"
        ],
        notes: [ "一過性の話題はscoreを控えめにしてください。" ]
      ),
      "clarity" => Template.new(
        source_type: "clarity",
        title: "Clarity",
        recommended_format: "csv",
        csv_example: <<~CSV.strip,
          title,description,score,observation_type
          店舗詳細ページで地図クリック前に離脱,スクロール到達率が低い,85,engagement
        CSV
        text_example: "店舗詳細ページで地図クリック前に離脱",
        score_guide: [
          "離脱・迷い・クリック不足が明確なら高め",
          "CV導線に近い画面ほど加点"
        ],
        notes: [ "画面名、離脱位置、クリックされない要素をdescriptionに入れてください。" ]
      ),
      "google_business_profile" => Template.new(
        source_type: "google_business_profile",
        title: "Google Business Profile",
        recommended_format: "csv",
        csv_example: <<~CSV.strip,
          title,description,score,observation_type
          電話数が増加,特定店舗ジャンルで問い合わせ増,80,engagement
        CSV
        text_example: "電話数が増加",
        score_guide: [
          "電話・経路・サイトクリックが増えているなら高め",
          "特定ジャンルやエリアに偏りがあるなら加点"
        ],
        notes: [ "店舗ジャンル、エリア、増えた行動をdescriptionに入れてください。" ]
      )
    }.freeze

    class << self
      def all
        TEMPLATES
      end

      def csv_header
        CSV_HEADER
      end
    end
  end
end
