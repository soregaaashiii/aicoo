require "test_helper"

class AnalyticsSourceSettingValidationTest < ActiveSupport::TestCase
  test "does not allow duplicate enabled gsc site url" do
    AnalyticsSourceSetting.create!(
      source_type: "gsc",
      name: "Primary GSC",
      site_url: "sc-domain:suelog.jp",
      enabled: true
    )

    duplicate = AnalyticsSourceSetting.new(
      source_type: "gsc",
      name: "Duplicate GSC",
      site_url: "sc-domain:suelog.jp",
      enabled: true
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:site_url], "同じGSCサイトURLの有効設定が既に存在します"
  end

  test "does not allow duplicate enabled ga4 property id" do
    AnalyticsSourceSetting.create!(
      source_type: "ga4",
      name: "Primary GA4",
      property_id: "123456789",
      enabled: true
    )

    duplicate = AnalyticsSourceSetting.new(
      source_type: "ga4",
      name: "Duplicate GA4",
      property_id: "123456789",
      enabled: true
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:property_id], "同じGA4プロパティIDの有効設定が既に存在します"
  end

  test "allows duplicate disabled settings" do
    AnalyticsSourceSetting.create!(
      source_type: "gsc",
      name: "Disabled GSC 1",
      site_url: "sc-domain:suelog.jp",
      enabled: false
    )

    duplicate = AnalyticsSourceSetting.new(
      source_type: "gsc",
      name: "Disabled GSC 2",
      site_url: "sc-domain:suelog.jp",
      enabled: false
    )

    assert duplicate.valid?
  end

  test "does not allow editing into duplicate enabled setting" do
    AnalyticsSourceSetting.create!(
      source_type: "ga4",
      name: "Primary GA4",
      property_id: "123456789",
      enabled: true
    )
    setting = AnalyticsSourceSetting.create!(
      source_type: "ga4",
      name: "Other GA4",
      property_id: "987654321",
      enabled: true
    )

    setting.property_id = "123456789"

    assert_not setting.valid?
    assert_includes setting.errors[:property_id], "同じGA4プロパティIDの有効設定が既に存在します"
  end
end
