require "test_helper"

module Aicoo
  module Lovable
    class PipelineDiagnosisSnapshotTest < ActiveSupport::TestCase
      test "round trips the saved diagnosis without running diagnosis again" do
        run = create_run
        result = diagnosis_result

        PipelineDiagnosisSnapshot.write!(
          generation_run: run,
          result:,
          source: "manual_recheck"
        )
        loaded = PipelineDiagnosisSnapshot.read(run.reload)

        assert_equal result.level, loaded.level
        assert_equal result.status_label, loaded.status_label
        assert_equal result.next_action, loaded.next_action
        assert_equal result.components.map(&:to_h), loaded.components.map(&:to_h)
        assert_equal "manual_recheck", run.metadata.dig(PipelineDiagnosisSnapshot::METADATA_KEY, "source")
      end

      test "uses saved summaries for multiple landing pages without queries" do
        error_run = Struct.new(:metadata).new({
          PipelineDiagnosisSnapshot::METADATA_KEY => {
            "summary" => { "label" => "GitHub設定不足", "level" => "error" }
          }
        })
        healthy_run = Struct.new(:metadata).new({
          PipelineDiagnosisSnapshot::METADATA_KEY => {
            "summary" => { "label" => "すべて正常", "level" => "healthy" }
          }
        })
        page_class = Struct.new(:metadata)

        summary = PipelineDiagnosisSnapshot.summary_for(
          landing_pages: [
            page_class.new({ "lovable_generation_run_id" => 10 }),
            page_class.new({ "lovable_generation_run_id" => 11 })
          ],
          generation_runs_by_id: { 10 => healthy_run, 11 => error_run }
        )

        assert_equal "GitHub設定不足", summary.label
        assert_equal "error", summary.level
      end

      test "keeps recheck available for a legacy failed pipeline without a full snapshot" do
        run = Struct.new(:metadata).new({
          "lovable_error_code" => "github_permission_error",
          "pipeline_status" => "github_webhook_waiting"
        })

        result = PipelineDiagnosisSnapshot.unavailable_result(run)

        assert result.component(:github).recheckable
        assert_equal "error", result.component(:github).level
      end

      test "refreshes on repository registration webhook pipeline state and daily run changes" do
        sources = []
        refresher = lambda do |generation_run:, source:|
          sources << [ generation_run.id, source ]
        end
        run = nil

        PipelineDiagnosisRefresher.stub(:call, refresher) do
          run = AicooLabGenerationRun.create!(
            generation_type: "lp_generation",
            status: "running",
            metadata: {
              "pipeline" => "lovable",
              "pipeline_status" => "artifact_fetching",
              "repository_import" => true
            }
          )
          run.update!(metadata: run.metadata.to_h.merge(
            "pipeline_status" => "github_webhook_received",
            "github_webhook_received_at" => Time.current.iso8601
          ))
          run.update!(metadata: run.metadata.to_h.merge("pipeline_status" => "static_building"))
          run.update!(metadata: run.metadata.to_h.merge(
            "pipeline_status" => "improvement_waiting",
            "measurement_checked_at" => Time.current.iso8601
          ))
        end

        assert_equal %w[
          repository_registration
          webhook
          pipeline_state_change
          daily_run
        ], sources.map(&:last)
      end

      private

      def create_run
        PipelineDiagnosisRefresher.stub(:call, nil) do
          AicooLabGenerationRun.create!(
            generation_type: "lp_generation",
            status: "running",
            metadata: {
              "pipeline" => "lovable",
              "pipeline_status" => "github_webhook_waiting"
            }
          )
        end
      end

      def diagnosis_result
        component = PipelineDiagnosis::Component.new(
          key: :github,
          label: "GitHub",
          level: "settings",
          status_label: "要設定",
          connection_status: "NG",
          cause: "Token権限が不足しています。",
          required_setting: "Contents Read",
          settings_location: "GitHub Settings",
          fix_steps: [ "Tokenを更新する" ],
          recheckable: true,
          details: { "Repository" => "example/lp" }
        )
        PipelineDiagnosis::Result.new(
          level: "settings",
          status_label: "要設定",
          components: [ component ],
          next_action: PipelineDiagnosis::NextAction.new(
            text: "Tokenを更新する",
            kind: :recheck,
            component: :github
          )
        )
      end
    end
  end
end
