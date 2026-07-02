module Aicoo
  module TrafficChannels
    class Registry
      Channel = Data.define(:key, :label, :description, :detail_route, :manual)

      CHANNELS = [
        Channel.new(key: "serp", label: "SERP", description: "検索需要・競合分析", detail_route: :admin_serp_settings_path, manual: false),
        Channel.new(key: "x", label: "X", description: "SNS投稿・検索", detail_route: nil, manual: true),
        Channel.new(key: "reddit", label: "Reddit", description: "海外コミュニティ調査", detail_route: nil, manual: true),
        Channel.new(key: "note", label: "note", description: "note記事・導線", detail_route: nil, manual: true),
        Channel.new(key: "hatena_bookmark", label: "はてなブックマーク", description: "話題化・被リンク", detail_route: nil, manual: true),
        Channel.new(key: "seo_article", label: "SEO記事", description: "記事流入", detail_route: nil, manual: false),
        Channel.new(key: "small_ads", label: "少額広告", description: "小額テスト広告", detail_route: nil, manual: true),
        Channel.new(key: "manual_share", label: "手動共有", description: "手動投稿・紹介", detail_route: nil, manual: true)
      ].freeze

      def self.channels
        CHANNELS
      end

      def self.keys
        CHANNELS.map(&:key)
      end

      def self.find(key)
        CHANNELS.find { |channel| channel.key == key.to_s }
      end
    end
  end
end
