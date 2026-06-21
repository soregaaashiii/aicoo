module Admin
  module AicooLab
    class ScoringQueueController < ApplicationController
      TARGET_DAYS = [ 7, 30, 90 ].freeze

      def index
        @entries = scoring_entries
      end

      def score
        AicooLabScoringResultCreator.new(experiment, target_days:).call
        redirect_to admin_aicoo_lab_scoring_queue_path, notice: "#{target_days} day scoring results were created."
      end

      def snapshot
        @experiment = experiment
        @target_days = target_days
        @snapshot = latest_landing_page_snapshot
        @snapshot_metrics = snapshot_metrics(@snapshot)
      end

      def score_snapshot
        snapshot = latest_landing_page_snapshot
        if snapshot
          AicooLabScoringResultCreator.new(experiment, target_days:, metrics: snapshot_metrics(snapshot)).call
          redirect_to admin_aicoo_lab_scoring_queue_path, notice: "#{target_days} day scoring results were created from DataHub Snapshot."
        else
          redirect_to admin_aicoo_lab_scoring_queue_path, alert: "DataHub Snapshot was not found."
        end
      end

      def hold
        experiment.update!(due_column => 1.day.from_now)
        redirect_to admin_aicoo_lab_scoring_queue_path, notice: "#{target_days} day scoring was held."
      end

      def fail
        AicooLabScoringResultCreator.new(experiment, target_days:, failure: true).call
        experiment.mark_status!("failed")
        redirect_to admin_aicoo_lab_scoring_queue_path, notice: "#{target_days} day failure scoring was created."
      end

      def reevaluate
        experiment.mark_status!("reevaluate")
        redirect_to admin_aicoo_lab_scoring_queue_path, notice: "Experiment was sent to reevaluation."
      end

      private

      def scoring_entries
        AicooLabExperiment.includes(:aicoo_lab_landing_page).where(status: "running").flat_map do |experiment|
          TARGET_DAYS.filter_map do |target_days|
            ScoringEntry.new(experiment:, target_days:) if due?(experiment, target_days)
          end
        end.sort_by { |entry| [ -entry.experiment.lab_priority_score.to_d, -entry.experiment.expected_value_score.to_d ] }
      end

      def due?(experiment, target_days)
        due_at = experiment.public_send(due_column_for(target_days))
        scored_at = experiment.public_send(scored_column_for(target_days))
        due_at.present? && due_at <= Time.current && scored_at.blank?
      end

      def experiment
        @experiment ||= AicooLabExperiment.find(params.expect(:experiment_id))
      end

      def target_days
        @target_days ||= Integer(params.expect(:target_days))
      end

      def due_column
        due_column_for(target_days)
      end

      def due_column_for(target_days)
        :"score_due_#{target_days}d_at"
      end

      def scored_column_for(target_days)
        :"scored_#{target_days}d_at"
      end

      def latest_landing_page_snapshot
        landing_page = experiment.aicoo_lab_landing_page
        snapshot = AicooDataSnapshot.where(source_type: "landing_page", source_id: landing_page.id).recent.first if landing_page
        return snapshot if snapshot

        AicooDataSnapshot.where(source_type: "landing_page")
                         .where("payload ->> 'experiment_id' = ?", experiment.id.to_s)
                         .recent
                         .first
      end

      def snapshot_metrics(snapshot)
        payload = snapshot&.payload || {}
        {
          pv: payload["pv"].to_i,
          cta_click: payload["cta_click"].to_i,
          signup: payload["signup"].to_i,
          cta_rate: payload["cta_rate"],
          signup_rate: payload["signup_rate"],
          sample_size: payload["pv"].to_i,
          sample_threshold_reached: payload["sample_threshold_reached"]
        }
      end

      ScoringEntry = Data.define(:experiment, :target_days) do
        def landing_page
          experiment.aicoo_lab_landing_page
        end

        def due_at
          experiment.public_send(:"score_due_#{target_days}d_at")
        end

        def pv
          landing_page&.view_count.to_i
        end

        def cta_clicks
          landing_page&.cta_click_count.to_i
        end

        def signups
          landing_page&.signup_count.to_i
        end

        def cta_rate
          landing_page&.cta_rate
        end

        def signup_rate
          landing_page&.signup_rate
        end

        def formal_score_possible?
          target_days == 90 || experiment.current_pv.to_i >= experiment.sample_pv_threshold.to_i || pv >= experiment.sample_pv_threshold.to_i
        end
      end
    end
  end
end
