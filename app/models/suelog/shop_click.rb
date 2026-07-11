module Suelog
  class ShopClick < SuelogRecord
    self.table_name = "shop_clicks"

    belongs_to :shop, class_name: "Suelog::Shop", foreign_key: :shop_id
    belongs_to :article, class_name: "Suelog::Article", foreign_key: :article_id, optional: true
  end
end
