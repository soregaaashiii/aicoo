module AicooInsight
  class Generator
    Result = Data.define(:created, :skipped) do
      def created_count
        created.size
      end

      def skipped_count
        skipped.size
      end
    end

    CandidateSpec = Data.define(
      :business,
      :title,
      :description,
      :action_type,
      :expected_profit_yen,
      :success_probability,
      :expected_hours,
      :cost_yen,
      :neglect_loss_90d_yen,
      :reason,
      :execution_prompt
    )

    DATE_KEYS = %w[date recorded_on occurred_on event_date].freeze

    def self.generate_all!(source: nil)
      return generate_all_without_run! if source.blank?

      run = AicooInsightGenerationRun.create!(source:, status: "running", started_at: Time.current)
      result = generate_all_without_run!
      run.update!(
        status: "success",
        finished_at: Time.current,
        generated_count: result.created_count,
        skipped_count: result.skipped_count
      )
      result
    rescue StandardError => e
      run&.update!(
        status: "failed",
        finished_at: Time.current,
        error_message: "#{e.class}: #{e.message}"
      )
      raise
    end

    def self.generate_all_without_run!
      created = []
      skipped = []

      Business.find_each do |business|
        result = new(business:).call
        created.concat(result.created)
        skipped.concat(result.skipped)
      end

      Result.new(created:, skipped:)
    end

    def initialize(business:)
      @business = business
    end

    def call
      specs = [
        ctr_improvement_specs,
        position_improvement_specs,
        revenue_improvement_specs,
        neglect_alert_specs,
        growth_expansion_specs,
        withdrawal_specs
      ].flatten.compact

      created = []
      skipped = []
      specs.each do |spec|
        if duplicate?(spec)
          skipped << spec
        else
          created << create_action_candidate!(spec)
        end
      end

      Result.new(created:, skipped:)
    end

    private

    attr_reader :business

    def ctr_improvement_specs
      gsc_rows.filter_map do |row|
        impressions = numeric(row, "impressions")
        clicks = numeric(row, "clicks")
        ctr = ratio(row["ctr"] || row[:ctr], clicks, impressions)
        position = decimal(row, "position")
        next unless impressions > 100 && ctr < 0.01 && position <= 10

        keyword = row_label(row)
        build_spec(
          title: "#{business.name}: #{keyword} のCTR改善",
          description: "表示回数は#{impressions}ありますが、CTRが#{percentage(ctr)}に留まっています。",
          action_type: "seo_improvement",
          expected_profit_yen: estimated_value(impressions, 0.02, 120),
          success_probability: 0.45,
          expected_hours: 1.5,
          reason: "CTR改善: 表示回数#{impressions} / CTR #{percentage(ctr)} / 順位 #{position.round(1)}",
          execution_prompt: "#{keyword} のSEOタイトルとメタディスクリプションを改善し、検索意図に合う訴求へ更新してください。"
        )
      end
    end

    def position_improvement_specs
      gsc_rows.filter_map do |row|
        position = decimal(row, "position")
        next unless position >= 5 && position <= 20

        impressions = numeric(row, "impressions")
        keyword = row_label(row)
        build_spec(
          title: "#{business.name}: #{keyword} の順位改善",
          description: "検索順位が#{position.round(1)}位で、内部リンクや関連記事追加による押し上げ余地があります。",
          action_type: "seo_improvement",
          expected_profit_yen: estimated_value([ impressions, 100 ].max, 0.015, 100),
          success_probability: 0.4,
          expected_hours: 2,
          reason: "順位改善: #{position.round(1)}位 / 表示回数#{impressions}",
          execution_prompt: "#{keyword} の対象ページに内部リンク、関連記事、比較導線を追加してください。既存URLは維持してください。"
        )
      end
    end

    def revenue_improvement_specs
      recent_pageviews = recent_metric_total(:pageviews, 30)
      return [] unless recent_pageviews > 300 && business.current_month_profit <= 1_000

      [
        build_spec(
          title: "#{business.name}: PVの多いページの収益導線改善",
          description: "直近30日のPVは#{recent_pageviews}ありますが、今月利益が#{business.current_month_profit}円に留まっています。",
          action_type: "sales",
          expected_profit_yen: [ (recent_pageviews * 8).round, 3_000 ].max,
          success_probability: 0.35,
          expected_hours: 2,
          reason: "収益改善: PV #{recent_pageviews} / 今月利益 #{business.current_month_profit}円",
          execution_prompt: "PVが多いページを確認し、広告配置、アフィリエイト導線、問い合わせ導線を1つ改善してください。"
        )
      ]
    end

    def neglect_alert_specs
      business.action_candidates.active_for_ranking.where("neglect_loss_90d_yen > 0").limit(3).map do |action|
        build_spec(
          title: "#{business.name}: 放置損失対策 - #{action.title}",
          description: "放置損失#{action.neglect_loss_90d_yen}円が設定されているため、順位維持やリンク修正を優先します。",
          action_type: "seo_improvement",
          expected_profit_yen: action.neglect_loss_90d_yen.to_i,
          success_probability: 0.5,
          expected_hours: [ action.expected_hours.to_d, 1 ].max,
          neglect_loss_90d_yen: action.neglect_loss_90d_yen,
          reason: "放置アラート: 放置損失 #{action.neglect_loss_90d_yen}円",
          execution_prompt: "#{action.title} を確認し、古い情報、リンク切れ、内部リンク不足を修正してください。"
        )
      end
    end

    def growth_expansion_specs
      current_clicks = metric_total(:clicks, 7.days.ago.to_date..Date.current)
      previous_clicks = metric_total(:clicks, 14.days.ago.to_date...7.days.ago.to_date)
      current_pageviews = metric_total(:pageviews, 7.days.ago.to_date..Date.current)
      previous_pageviews = metric_total(:pageviews, 14.days.ago.to_date...7.days.ago.to_date)
      growth_rate = growth_rate(current_clicks + current_pageviews, previous_clicks + previous_pageviews)
      return [] unless growth_rate > 0.3 && (current_clicks + current_pageviews) >= 20

      [
        build_spec(
          title: "#{business.name}: 伸びている記事を横展開",
          description: "直近7日のクリック/PVが前週比#{percentage(growth_rate)}伸びています。",
          action_type: "seo_article",
          expected_profit_yen: [ ((current_clicks + current_pageviews) * 20).round, 2_000 ].max,
          success_probability: 0.5,
          expected_hours: 2,
          reason: "成長記事拡張: 前週比 #{percentage(growth_rate)}",
          execution_prompt: "伸びている検索流入ページを特定し、関連記事追加、エリア展開、内部リンク追加を行ってください。"
        )
      ]
    end

    def withdrawal_specs
      metric_days = business.business_metric_dailies.where(recorded_on: 30.days.ago.to_date..Date.current)
      return [] unless metric_days.size >= 14
      return [] unless metric_days.sum(&:proxy_score) < 10 && business.cumulative_profit <= 0 && business.action_candidates.active_for_ranking.sum(:neglect_loss_90d_yen).to_i.zero?

      [
        build_spec(
          title: "#{business.name}: 低反応施策の停止検討",
          description: "直近30日の反応と利益が弱く、放置損失も低いため、継続判断の見直し候補です。",
          action_type: "withdraw",
          expected_profit_yen: 1_000,
          success_probability: 0.3,
          expected_hours: 1,
          reason: "撤退候補: 30日proxy_score低迷 / 累計利益 #{business.cumulative_profit}円 / 放置損失低",
          execution_prompt: "この事業の継続条件、停止条件、最小限の保守範囲を整理し、保留または撤退判断を提案してください。"
        )
      ]
    end

    def build_spec(title:, description:, action_type:, expected_profit_yen:, success_probability:, expected_hours:, reason:, execution_prompt:, cost_yen: 0, neglect_loss_90d_yen: 0)
      CandidateSpec.new(
        business:,
        title:,
        description:,
        action_type:,
        expected_profit_yen: expected_profit_yen.to_i,
        success_probability:,
        expected_hours:,
        cost_yen:,
        neglect_loss_90d_yen:,
        reason:,
        execution_prompt:
      )
    end

    def duplicate?(spec)
      ActionCandidate.where(
        business: spec.business,
        title: spec.title,
        action_type: spec.action_type,
        created_at: 30.days.ago..
      ).exists?
    end

    def create_action_candidate!(spec)
      probability = [ spec.success_probability.to_d, 0.01.to_d ].max
      immediate_value = (spec.expected_profit_yen.to_d / probability).round

      spec.business.action_candidates.create!(
        title: spec.title,
        description: spec.description,
        action_type: spec.action_type,
        immediate_value_yen: immediate_value,
        success_probability: spec.success_probability,
        expected_hours: spec.expected_hours,
        cost_yen: spec.cost_yen,
        neglect_loss_90d_yen: spec.neglect_loss_90d_yen,
        generation_source: "ai_insight",
        status: "idea",
        confidence_score: confidence_for(spec),
        data_confidence_score: 70,
        evaluation_reason: spec.reason,
        execution_prompt: spec.execution_prompt,
        metadata: { "insight_rule" => insight_rule(spec), "insight_reason" => spec.reason }
      )
    end

    def confidence_for(spec)
      case spec.action_type
      when "seo_improvement" then 72
      when "seo_article" then 68
      when "sales" then 62
      when "withdraw" then 50
      else 55
      end
    end

    def insight_rule(spec)
      return "neglect_alert" if spec.neglect_loss_90d_yen.to_i.positive?
      return "withdrawal" if spec.action_type == "withdraw"
      return "revenue_improvement" if spec.action_type == "sales"
      return "growth_expansion" if spec.action_type == "seo_article"
      return "ctr_improvement" if spec.title.include?("CTR")

      "position_improvement"
    end

    def gsc_rows
      snapshot_rows("gsc")
    end

    def snapshot_rows(source_type)
      matching_snapshots(source_type).flat_map do |snapshot|
        rows = rows_from_payload(snapshot.payload || {})
        rows.presence || [ snapshot.payload || {} ]
      end
    end

    def rows_from_payload(payload)
      rows = payload["rows"] || payload.dig("metrics", "rows")
      rows = payload["metrics"] if rows.blank? && payload["metrics"].is_a?(Array)
      Array(rows).select { |row| row.is_a?(Hash) }
    end

    def matching_snapshots(source_type)
      AicooDataSnapshot.where(source_type:).select do |snapshot|
        snapshot_business_id(snapshot) == business.id
      end
    end

    def snapshot_business_id(snapshot)
      payload = snapshot.payload || {}
      payload["business_id"].presence&.to_i ||
        business_id_from_analytics_site(payload["analytics_site_id"]) ||
        business_id_from_data_import(snapshot)
    end

    def business_id_from_analytics_site(analytics_site_id)
      return if analytics_site_id.blank?

      AicooAnalyticsSite.find_by(id: analytics_site_id)&.business_id
    end

    def business_id_from_data_import(snapshot)
      return unless %w[gsc ga4].include?(snapshot.source_type)

      DataImport.find_by(id: snapshot.source_id)&.business&.id
    end

    def recent_metric_total(metric, days)
      metric_total(metric, (days - 1).days.ago.to_date..Date.current)
    end

    def metric_total(metric, range)
      business.business_metric_dailies.where(recorded_on: range).sum(metric).to_i
    end

    def growth_rate(current, previous)
      return 1.0 if current.positive? && previous.zero?
      return 0.0 if previous.zero?

      (current.to_d - previous.to_d) / previous.to_d
    end

    def estimated_value(impressions, lift, yen_per_click)
      [ (impressions.to_d * lift.to_d * yen_per_click).round, 1_000 ].max
    end

    def row_label(row)
      row["query"].presence || row[:query].presence || row["page"].presence || row[:page].presence || "対象ページ"
    end

    def numeric(hash, key)
      metrics = hash["metrics"].is_a?(Hash) ? hash["metrics"] : {}
      value = hash[key] || hash[key.to_sym] || metrics[key] || metrics[key.to_sym]
      value.to_f.round
    end

    def decimal(hash, key)
      metrics = hash["metrics"].is_a?(Hash) ? hash["metrics"] : {}
      value = hash[key] || hash[key.to_sym] || metrics[key] || metrics[key.to_sym]
      value.to_d
    end

    def ratio(raw_value, numerator, denominator)
      return raw_value.to_d if raw_value.present?
      return 0.to_d if denominator.to_i.zero?

      numerator.to_d / denominator.to_d
    end

    def percentage(value)
      "#{(value.to_d * 100).round(1)}%"
    end
  end
end
