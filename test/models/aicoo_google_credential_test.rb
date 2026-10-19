require "test_helper"

class AicooGoogleCredentialTest < ActiveSupport::TestCase
  test "default prefers a saved oauth client over a newer blank credential" do
    AicooGoogleCredential.update_all(enabled: false)
    configured = AicooGoogleCredential.create!(
      name: "保存済みGoogle認証",
      client_id: "saved-client",
      client_secret: "saved-secret",
      enabled: true,
      created_at: 2.days.ago
    )
    AicooGoogleCredential.create!(
      name: "空のGoogle認証",
      enabled: true,
      created_at: 1.day.ago
    )

    assert_equal configured, AicooGoogleCredential.default
  end

  test "default keeps the newest enabled credential when no oauth client is configured" do
    AicooGoogleCredential.update_all(enabled: false)
    older = AicooGoogleCredential.create!(name: "古いGoogle認証", enabled: true, created_at: 2.days.ago)
    newer = AicooGoogleCredential.create!(name: "新しいGoogle認証", enabled: true, created_at: 1.day.ago)

    assert_equal newer, AicooGoogleCredential.default
    assert_not_equal older, AicooGoogleCredential.default
  end
end
