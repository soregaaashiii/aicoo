require "test_helper"

module Admin
  class ExternalCommitImportsControllerTest < ActionDispatch::IntegrationTest
    test "shows new external commit import form" do
      get new_admin_external_commit_import_url(
        business_id: businesses(:suelog).id,
        action_candidate_id: action_candidates(:nagazakicho_article).id,
        commit_sha: "bcc4a2c"
      )

      assert_response :success
      assert_includes response.body, "外部commit取り込み"
      assert_includes response.body, "bcc4a2c"
    end

    test "creates import records" do
      candidate = action_candidates(:nagazakicho_article)

      assert_difference(-> { BusinessActivityLog.where(activity_type: "code_revision_imported").count }, 1) do
        post admin_external_commit_imports_url, params: {
          external_commit_import: {
            business_id: businesses(:suelog).id,
            action_candidate_id: candidate.id,
            repository: "soregaaashiii/suelog",
            commit_sha: "bcc4a2c",
            changed_files: "app/views/shops/show.html.erb",
            result_summary: "店舗詳細のCV導線を改善しました。",
            test_result: "git diff --check OK"
          }
        }
      end

      assert_redirected_to action_result_url(candidate.reload.action_result)
      assert_equal "外部commitをAICOOへ取り込みました。ActionResultとActivity Logに反映しました。", flash[:notice]
    end
  end
end
