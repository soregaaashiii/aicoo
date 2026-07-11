module Suelog
  class Shop < SuelogRecord
    self.table_name = "shops"

    has_many :shop_clicks, class_name: "Suelog::ShopClick", foreign_key: :shop_id

    UNKNOWN_SMOKING_AREA = 2
    UNKNOWN_SMOKING_TYPE = 3

    scope :approved, -> { where(approved: true) }
    scope :verification_needed, lambda {
      where(
        "smoking_unverified = TRUE OR smoking_area = :unknown_area OR smoking_type = :unknown_type OR last_confirmed_on IS NULL OR last_confirmed_on < :stale_on OR on_hold = TRUE OR hold_reason IN (:hold_reasons)",
        unknown_area: UNKNOWN_SMOKING_AREA,
        unknown_type: UNKNOWN_SMOKING_TYPE,
        stale_on: 180.days.ago.to_date,
        hold_reasons: %w[tabelog_suspect unverified]
      )
    }

    def smoking_area_label
      { 0 => "分煙", 1 => "全席喫煙", 2 => "不明" }.fetch(smoking_area, smoking_area.to_s.presence || "未設定")
    end

    def smoking_type_label
      { 0 => "紙・加熱式OK", 1 => "加熱式のみ", 2 => "紙タバコのみ", 3 => "不明" }.fetch(smoking_type, smoking_type.to_s.presence || "未設定")
    end

    def stale_verification?
      last_confirmed_on.blank? || last_confirmed_on < 180.days.ago.to_date
    end
  end
end
