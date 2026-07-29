module Aicoo
  class BusinessTimeline
    Item = Struct.new(:occurred_at, :event_type, :title, :description, :path, keyword_init: true)

    def initialize(
      business,
      limit: 40,
      landing_pages: nil,
      metrics: nil,
      revenue_events: nil,
      action_candidates: nil,
      action_executions: nil,
      action_results: nil,
      auto_revision_tasks: nil,
      activity_logs: nil,
      business_services: nil
    )
      @business = business
      @limit = limit
      @landing_pages = landing_pages
      @metrics = metrics
      @revenue_events = revenue_events
      @action_candidates = action_candidates
      @action_executions = action_executions
      @action_results = action_results
      @auto_revision_tasks = auto_revision_tasks
      @activity_logs = activity_logs
      @business_services = business_services
    end

    def call
      [
        business_created_item,
        landing_page_items,
        metric_items,
        revenue_items,
        improvement_items,
        activity_items,
        service_items,
        playbook_item
      ].flatten.compact.sort_by(&:occurred_at).reverse.first(limit)
    end

    private

    attr_reader :business, :limit

    def business_created_item
      Item.new(
        occurred_at: business.created_at,
        event_type: "business_created",
        title: "Idea作成",
        description: business.description.to_s.truncate(80),
        path: Rails.application.routes.url_helpers.business_path(business)
      )
    end

    def landing_page_items
      rows = @landing_pages || business.aicoo_lab_landing_pages.to_a
      rows.flat_map do |landing_page|
        items = [
          Item.new(
            occurred_at: landing_page.created_at,
            event_type: "lp_created",
            title: "LP生成",
            description: landing_page.headline,
            path: Rails.application.routes.url_helpers.admin_aicoo_lab_edit_public_landing_page_path(landing_page)
          )
        ]
        if landing_page.published_at
          items << Item.new(
            occurred_at: landing_page.published_at,
            event_type: "lp_published",
            title: "LP公開",
            description: landing_page.public_headline,
            path: landing_page.published_slug.present? ? Rails.application.routes.url_helpers.public_lp_path(landing_page.published_slug) : nil
          )
        end
        items
      end
    end

    def metric_items
      latest_metric = if @metrics
        @metrics.max_by(&:recorded_on)
      else
        business.business_metric_dailies.order(recorded_on: :desc).first
      end
      return unless latest_metric

      Item.new(
        occurred_at: latest_metric.updated_at,
        event_type: "analytics_updated",
        title: "GA4/GSC計測更新",
        description: "clicks #{latest_metric.clicks} / sessions #{latest_metric.sessions} / pageviews #{latest_metric.pageviews}",
        path: Rails.application.routes.url_helpers.business_path(business, anchor: "analytics")
      )
    end

    def revenue_items
      rows = @revenue_events ? @revenue_events.sort_by(&:created_at).reverse.first(10) : business.revenue_events.order(created_at: :desc).limit(10)
      rows.map do |event|
        Item.new(
          occurred_at: event.created_at,
          event_type: event.event_type,
          title: event.revenue? ? "売上記録" : "費用記録",
          description: "#{event.occurred_on} / #{event.amount}円",
          path: Rails.application.routes.url_helpers.revenue_event_path(event)
        )
      end
    end

    def improvement_items
      action_items + execution_items + result_items + auto_revision_items
    end

    def action_items
      rows = @action_candidates ? @action_candidates.sort_by(&:created_at).reverse.first(10) : business.action_candidates.order(created_at: :desc).limit(10)
      rows.map do |candidate|
        Item.new(
          occurred_at: candidate.created_at,
          event_type: "proposal_created",
          title: "改善提案",
          description: candidate.title,
          path: Rails.application.routes.url_helpers.action_candidate_path(candidate)
        )
      end
    end

    def execution_items
      rows = @action_executions || ActionExecution.joins(:action_candidate)
                                                  .where(action_candidates: { business_id: business.id })
                                                  .recent
                                                  .limit(10)
      rows.map do |execution|
        Item.new(
          occurred_at: execution.updated_at,
          event_type: "action_execution",
          title: "改善実施",
          description: "#{execution.status} / #{execution.action_candidate.title}",
          path: Rails.application.routes.url_helpers.action_execution_path(execution)
        )
      end
    end

    def result_items
      rows = @action_results || business.action_results.order(created_at: :desc).limit(10)
      rows.map do |result|
        Item.new(
          occurred_at: result.created_at,
          event_type: "action_result",
          title: "結果登録",
          description: result.note.to_s.truncate(80),
          path: Rails.application.routes.url_helpers.action_result_path(result)
        )
      end
    end

    def auto_revision_items
      rows = @auto_revision_tasks || business.auto_revision_tasks.order(created_at: :desc).limit(10)
      rows.map do |task|
        Item.new(
          occurred_at: task.created_at,
          event_type: "codex_revision",
          title: "Codex改修",
          description: "#{task.status} / #{task.title}",
          path: Rails.application.routes.url_helpers.auto_revision_task_path(task)
        )
      end
    end

    def activity_items
      rows = @activity_logs || business.business_activity_logs.recent.limit(10)
      rows.map do |activity_log|
        Item.new(
          occurred_at: activity_log.occurred_at,
          event_type: activity_log.activity_type,
          title: "Activity検知",
          description: activity_log.title,
          path: Rails.application.routes.url_helpers.admin_business_activity_log_path(activity_log)
        )
      end
    end

    def service_items
      rows = @business_services ? @business_services.first(10) : business.business_services.recent.limit(10)
      rows.map do |service|
        Item.new(
          occurred_at: service.created_at,
          event_type: "service_registered",
          title: "Service登録",
          description: "#{service.name} / #{service.status}",
          path: Rails.application.routes.url_helpers.business_path(business, anchor: "business-services")
        )
      end
    end

    def playbook_item
      return unless business.business_playbook&.last_calculated_at

      Item.new(
        occurred_at: business.business_playbook.last_calculated_at,
        event_type: "learning_updated",
        title: "学習更新",
        description: "Business Playbook confidence #{business.business_playbook.confidence_score}",
        path: Rails.application.routes.url_helpers.business_path(business, anchor: "business-learning")
      )
    end
  end
end
