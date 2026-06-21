module Admin
  module AicooLab
    module ExperimentsHelper
      STATUS_LABELS = {
        "draft" => "下書き",
        "preview_ready" => "LP作成済み",
        "approval_pending" => "承認待ち",
        "running" => "検証中",
        "paused" => "停止中",
        "success" => "成功",
        "failed" => "失敗",
        "reevaluate" => "再評価待ち"
      }.freeze

      APPROVAL_STATUS_LABELS = {
        "not_required" => "未申請",
        "pending" => "承認待ち",
        "approved" => "承認済み",
        "rejected" => "却下"
      }.freeze

      def aicoo_lab_status_label(status)
        STATUS_LABELS.fetch(status, status)
      end

      def aicoo_lab_approval_status_label(status)
        APPROVAL_STATUS_LABELS.fetch(status, status)
      end

      def aicoo_lab_next_operation(experiment)
        return "完了" if %w[success failed].include?(experiment.status)
        return "採点待ち" if aicoo_lab_scoring_due?(experiment)
        return "検証中" if experiment.status == "running"
        return "検証開始待ち" if experiment.approval_status == "approved"
        return "承認待ち" if experiment.status == "approval_pending" || experiment.approval_status == "pending"
        return "レビュー待ち" if experiment.status == "preview_ready"

        experiment.aicoo_lab_landing_page ? "プレビュー準備待ち" : "LP作成待ち"
      end

      def aicoo_lab_next_operation_label(experiment)
        return "完了済み" if %w[success failed].include?(experiment.status)
        return "LP URLに流入させる / 採点待ちを確認" if experiment.status == "running"
        return "承認済み未開始へ進む" if experiment.status == "approval_pending" && experiment.approval_status == "approved"
        return "検証開始" if experiment.approval_status == "approved"
        return "LPを確認してレビューする" if experiment.status == "preview_ready"
        return "承認する / 却下する" if experiment.status == "approval_pending" || experiment.approval_status == "pending"

        experiment.aicoo_lab_landing_page ? "LP確認待ちに進める" : "LPを作成する"
      end

      def aicoo_lab_next_operation_path(experiment)
        return admin_aicoo_lab_scoring_queue_path if aicoo_lab_scoring_due?(experiment)
        return admin_aicoo_lab_scoring_queue_path if experiment.status == "running"
        return admin_aicoo_lab_approved_experiments_path if experiment.approval_status == "approved"
        return admin_aicoo_lab_review_queue_path if experiment.status == "preview_ready" || experiment.approval_status == "pending"

        admin_aicoo_lab_experiment_path(experiment)
      end

      def aicoo_lab_scoring_due?(experiment)
        now = Time.current
        experiment.status == "running" && [
          [ experiment.score_due_7d_at, experiment.scored_7d_at ],
          [ experiment.score_due_30d_at, experiment.scored_30d_at ],
          [ experiment.score_due_90d_at, experiment.scored_90d_at ]
        ].any? { |due_at, scored_at| due_at.present? && due_at <= now && scored_at.blank? }
      end

      def aicoo_lab_current_state_sentence
        messages = []
        messages << "事業アイデアがあります。LP化できます。" if AicooLabExperimentCandidate.where(status: %w[proposed approved]).exists?
        messages << "レビューが必要です。" if AicooLabExperiment.review_queue.exists?
        messages << "検証開始できます。" if AicooLabExperiment.approved_not_started.exists?
        messages << "採点待ちがあります。" if AicooLabExperimentSummaryProxy.scoring_queue_count.positive?
        messages.presence || [ "今すぐ処理すべき詰まりはありません。" ]
      end

      def aicoo_lab_inbox_items
        [
          aicoo_lab_inbox_item(
            "採点待ち",
            AicooLabExperimentSummaryProxy.scoring_queue_count,
            "結果が出た実験を採点して、AICOOの予測誤差を記録します。",
            "採点待ちを見る",
            admin_aicoo_lab_scoring_queue_path
          ),
          aicoo_lab_inbox_item(
            "承認待ち / LP確認待ち",
            AicooLabExperiment.review_queue.count,
            "LPプレビューを見て、検証として進めるか判断します。",
            "レビュー待ちを見る",
            admin_aicoo_lab_review_queue_path
          ),
          aicoo_lab_inbox_item(
            "承認済み未開始",
            AicooLabExperiment.approved_not_started.count,
            "承認済みの検証を開始して、採点タイマーを開始します。",
            "検証開始へ",
            admin_aicoo_lab_approved_experiments_path
          ),
          aicoo_lab_inbox_item(
            "事業アイデアあり",
            AicooLabExperimentCandidate.where(status: %w[proposed approved]).count,
            "良さそうなアイデアを選んで一括LP化できます。",
            "事業アイデアを見る",
            admin_aicoo_lab_candidates_path
          ),
          aicoo_lab_inbox_item(
            "AI提案あり",
            AicooLabAiDraft.where(status: %w[draft approved]).count,
            "AIが出したJSON候補をレビューして、事業アイデアとして取り込みます。",
            "AI提案を見る",
            admin_aicoo_lab_ai_drafts_path
          )
        ].select { |item| item.count.positive? }.presence || [
          aicoo_lab_inbox_item(
            "今すぐ事業アイデアを生成",
            0,
            "処理待ちはありません。次の実験候補を作るところから始めます。",
            "候補を生成する",
            admin_aicoo_lab_candidates_path
          )
        ]
      end

      def aicoo_lab_inbox_item(state, count, description, button_label, path)
        InboxItem.new(state, count, description, button_label, path)
      end

      InboxItem = Data.define(:state, :count, :description, :button_label, :path)

      class AicooLabExperimentSummaryProxy
        def self.scoring_queue_count
          due_count(:score_due_7d_at, :scored_7d_at) +
            due_count(:score_due_30d_at, :scored_30d_at) +
            due_count(:score_due_90d_at, :scored_90d_at)
        end

        def self.due_count(due_column, scored_column)
          AicooLabExperiment.where(status: "running")
                            .where(scored_column => nil)
                            .where("#{due_column} <= ?", Time.current)
                            .count
        end
      end
    end
  end
end
