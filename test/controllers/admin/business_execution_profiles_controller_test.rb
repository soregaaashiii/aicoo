require "test_helper"

module Admin
  class BusinessExecutionProfilesControllerTest < ActionDispatch::IntegrationTest
    test "index shows execution profiles" do
      BusinessExecutionProfile.create!(
        business: businesses(:suelog),
        repository_name: "suelog",
        repository_type: "rails"
      )

      get admin_business_execution_profiles_url

      assert_response :success
      assert_includes response.body, "Business Execution Profiles"
      assert_includes response.body, "suelog"
    end

    test "creates execution profile" do
      assert_difference("BusinessExecutionProfile.count", 1) do
        post admin_business_execution_profiles_url, params: {
          business_execution_profile: {
            business_id: businesses(:suelog).id,
            repository_name: "suelog",
            repository_type: "rails",
            repository_path: "/apps/suelog",
            github_repository: "kawamura/suelog",
            default_branch: "main",
            test_command: "bin/rails test",
            lint_command: "bundle exec rubocop",
            deploy_command: "bin/deploy",
            production_url: "https://suelog.example.com",
            codex_instructions: "SEO導線を壊さない",
            forbidden_patterns: "db:drop\ndb:reset",
            active: "1"
          }
        }
      end

      assert_redirected_to admin_business_execution_profiles_url
      profile = BusinessExecutionProfile.last
      assert_equal businesses(:suelog), profile.business
      assert_equal "rails", profile.repository_type
      assert_equal "kawamura/suelog", profile.github_repository
    end

    test "updates execution profile" do
      profile = BusinessExecutionProfile.create!(
        business: businesses(:suelog),
        repository_name: "suelog",
        repository_type: "rails"
      )

      patch admin_business_execution_profile_url(profile), params: {
        business_execution_profile: {
          business_id: businesses(:suelog).id,
          repository_name: "suelog-next",
          repository_type: "nextjs",
          default_branch: "main",
          active: "0"
        }
      }

      assert_redirected_to admin_business_execution_profiles_url
      profile.reload
      assert_equal "suelog-next", profile.repository_name
      assert_equal "nextjs", profile.repository_type
      assert_not profile.active?
    end
  end
end
