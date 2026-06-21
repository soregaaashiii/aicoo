module Admin
  module AicooRevenueHelper
    def aicoo_revenue_score(value)
      return "費用なし" if value == Float::INFINITY

      number_with_precision(value, precision: 4)
    end

    def aicoo_revenue_yen(value)
      number_to_currency(value, unit: "¥", precision: 0)
    end

    def aicoo_revenue_source_label(source)
      {
        "candidate" => "事業アイデア",
        "experiment" => "新規事業検証",
        "action_candidate" => "行動候補"
      }.fetch(source, source)
    end

    def aicoo_revenue_attack_value(row)
      row.expected_90d_profit_yen.to_d * row.success_probability.to_d
    end

    def aicoo_revenue_neglect_alert_badge(row)
      return unless row.neglect_alert

      tag.span("放置注意", class: "aicoo-lab-status-badge")
    end

    def aicoo_revenue_planned?(row)
      Array(@planned_execution_keys).include?("#{row.source}:#{row.source_id}")
    end

    def aicoo_revenue_plan_button(row, result)
      return tag.span("実行予定済み", class: "aicoo-lab-status-badge") if aicoo_revenue_planned?(row)

      button_to "実行予定にする", admin_aicoo_revenue_executions_path, method: :post, params: {
        aicoo_revenue_execution: {
          source_type: row.source,
          source_id: row.source_id,
          available_minutes: result.available_minutes,
          available_budget_yen: result.available_budget_yen,
          source: result.source
        }
      }, class: "button aicoo-revenue-primary-action"
    end

    def aicoo_revenue_source_path(execution)
      case execution.source_type
      when "candidate"
        admin_aicoo_lab_candidate_path(execution.source_id)
      when "experiment"
        admin_aicoo_lab_experiment_path(execution.source_id)
      when "action_candidate"
        action_candidate_path(execution.source_id)
      end
    end

    def aicoo_revenue_source_link(execution)
      if execution.source_record
        link_to execution.source_record.title, aicoo_revenue_source_path(execution)
      else
        "元データが見つかりません"
      end
    end
  end
end
