module Suelog
  class Article < SuelogRecord
    self.table_name = "articles"

    has_many :shop_clicks, class_name: "Suelog::ShopClick", foreign_key: :article_id

    scope :published, lambda {
      where(published: true)
        .where("published_at IS NULL OR published_at <= ?", Time.current)
    }

    def public_path
      "/articles/#{slug}"
    end

    def searchable_text
      [ title, seo_title, meta_description, summary, recommended_areas, slug ].compact.join(" ").downcase
    end
  end
end
