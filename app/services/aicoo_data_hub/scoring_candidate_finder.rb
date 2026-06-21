module AicooDataHub
  class ScoringCandidateFinder
    Candidate = Data.define(:target_type, :target_id, :title, :reason, :available_metrics, :suggested_action_url)

    def call
      lab_candidates + revenue_candidates
    end

    private

    def lab_candidates
      latest_landing_page_snapshots.filter_map do |snapshot|
        experiment = lab_experiment_for(snapshot)
        next unless experiment
        next unless lab_candidate?(experiment, snapshot)

        Candidate.new(
          target_type: "lab_experiment",
          target_id: experiment.id,
          title: experiment.title,
          reason: lab_reason(experiment),
          available_metrics: landing_page_metrics(snapshot),
          suggested_action_url: routes.admin_aicoo_lab_scoring_queue_snapshot_path(experiment, suggested_target_days(experiment))
        )
      end
    end

    def revenue_candidates
      latest_revenue_snapshots.filter_map do |snapshot|
        execution = AicooRevenueExecution.find_by(id: snapshot.source_id)
        next unless execution&.status == "done"
        next if execution.actual_90d_profit_yen.present?

        Candidate.new(
          target_type: "revenue_execution",
          target_id: execution.id,
          title: execution.title,
          reason: "RevenueExecutionはdoneですが、実績90日利益が未入力です。",
          available_metrics: revenue_metrics(snapshot),
          suggested_action_url: routes.edit_admin_aicoo_revenue_execution_path(execution)
        )
      end
    end

    def latest_landing_page_snapshots
      latest_snapshots("landing_page")
    end

    def latest_revenue_snapshots
      latest_snapshots("revenue_execution")
    end

    def latest_snapshots(source_type)
      AicooDataSnapshot
        .where(source_type:)
        .recent
        .to_a
        .uniq { |snapshot| [ snapshot.source_type, snapshot.source_id ] }
    end

    def lab_experiment_for(snapshot)
      experiment_id = snapshot.payload["experiment_id"]
      return AicooLabExperiment.find_by(id: experiment_id) if experiment_id.present?

      AicooLabLandingPage.find_by(id: snapshot.source_id)&.aicoo_lab_experiment
    end

    def lab_candidate?(experiment, snapshot)
      (experiment.status == "running" || lab_due?(experiment)) && landing_page_metrics_available?(snapshot)
    end

    def lab_due?(experiment)
      [
        [ experiment.score_due_7d_at, experiment.scored_7d_at ],
        [ experiment.score_due_30d_at, experiment.scored_30d_at ],
        [ experiment.score_due_90d_at, experiment.scored_90d_at ]
      ].any? { |due_at, scored_at| due_at.present? && due_at <= Time.current && scored_at.blank? }
    end

    def landing_page_metrics_available?(snapshot)
      landing_page_metrics(snapshot).values.any?(&:present?)
    end

    def landing_page_metrics(snapshot)
      {
        pv: snapshot.payload["pv"],
        cta_click: snapshot.payload["cta_click"],
        signup: snapshot.payload["signup"]
      }
    end

    def revenue_metrics(snapshot)
      {
        predicted_value: snapshot.payload["predicted_value"],
        actual_90d_profit_yen: snapshot.payload["actual_90d_profit_yen"],
        calibration_score: snapshot.payload["calibration_score"]
      }
    end

    def lab_reason(experiment)
      due_labels = []
      due_labels << "7日採点期限到達" if due_now?(experiment.score_due_7d_at, experiment.scored_7d_at)
      due_labels << "30日採点期限到達" if due_now?(experiment.score_due_30d_at, experiment.scored_30d_at)
      due_labels << "90日採点期限到達" if due_now?(experiment.score_due_90d_at, experiment.scored_90d_at)

      reason = []
      reason << "Lab実験がrunningです" if experiment.status == "running"
      reason.concat(due_labels)
      reason << "LandingPage SnapshotにPV/CTA/Signupがあります"
      "#{reason.join(' / ')}。"
    end

    def due_now?(due_at, scored_at)
      due_at.present? && due_at <= Time.current && scored_at.blank?
    end

    def suggested_target_days(experiment)
      return 7 if due_now?(experiment.score_due_7d_at, experiment.scored_7d_at)
      return 30 if due_now?(experiment.score_due_30d_at, experiment.scored_30d_at)
      return 90 if due_now?(experiment.score_due_90d_at, experiment.scored_90d_at)

      30
    end

    def routes
      Rails.application.routes.url_helpers
    end
  end
end
