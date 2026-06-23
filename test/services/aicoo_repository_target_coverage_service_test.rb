require "test_helper"

class AicooRepositoryTargetCoverageServiceTest < ActiveSupport::TestCase
  test "calculates configured incomplete missing inactive statuses and coverage rate" do
    suelog = businesses(:suelog)
    cards = businesses(:cards)
    extra_missing = Business.create!(name: "未設定事業", status: "idea")
    inactive_business = Business.create!(name: "無効事業", status: "building")

    BusinessExecutionProfile.create!(
      business: suelog,
      repository_name: "suelog",
      repository_type: "rails",
      repository_path: "/apps/suelog",
      github_repository: "kawamura/suelog",
      test_command: "bin/rails test",
      deploy_command: "bin/deploy"
    )
    BusinessExecutionProfile.create!(
      business: cards,
      repository_name: "cards",
      repository_type: "nextjs",
      repository_path: "/apps/cards"
    )
    BusinessExecutionProfile.create!(
      business: inactive_business,
      repository_name: "inactive",
      repository_type: "rails",
      repository_path: "/apps/inactive",
      github_repository: "kawamura/inactive",
      test_command: "bin/rails test",
      deploy_command: "bin/deploy",
      active: false
    )

    result = AicooRepositoryTargetCoverageService.new.call
    statuses = result.items.to_h { |item| [ item.business.name, item.status ] }

    assert_equal "configured", statuses[suelog.name]
    assert_equal "incomplete", statuses[cards.name]
    assert_equal "missing", statuses[extra_missing.name]
    assert_equal "inactive", statuses[inactive_business.name]
    assert_equal 4, result.total_businesses
    assert_equal 1, result.configured_businesses
    assert_equal 1, result.incomplete_profile_businesses
    assert_equal 1, result.missing_profile_businesses
    assert_equal 1, result.inactive_profile_businesses
    assert_equal 25.0, result.coverage_rate
  end
end
