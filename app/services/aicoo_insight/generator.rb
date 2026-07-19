module AicooInsight
  class Generator
    class Result
      attr_reader :created,
        :skipped,
        :created_count,
        :skipped_count,
        :failed_count,
        :processed_count,
        :total_count,
        :last_spec

      def initialize(created: [], skipped: [], created_count: nil, skipped_count: nil, failed_count: 0, processed_count: nil, total_count: nil, completed: false, last_spec: nil)
        @created = created
        @skipped = skipped
        @created_count = created_count || created.size
        @skipped_count = skipped_count || skipped.size
        @failed_count = failed_count
        @processed_count = processed_count || created.size + skipped.size
        @total_count = total_count
        @completed = completed
        @last_spec = last_spec
      end

      def +(other)
        self.class.new(
          created_count: created_count.to_i + other.created_count.to_i,
          skipped_count: skipped_count.to_i + other.skipped_count.to_i,
          failed_count: failed_count.to_i + other.failed_count.to_i,
          processed_count: processed_count.to_i + other.processed_count.to_i,
          skipped: (skipped + other.skipped).first(20)
        )
      end

      def completed?
        @completed
      end

      def with_batch_progress(processed_count:, total_count:, completed:, last_spec:)
        self.class.new(
          created:,
          skipped:,
          created_count:,
          skipped_count:,
          failed_count:,
          processed_count:,
          total_count:,
          completed:,
          last_spec:
        )
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
    DEFAULT_BATCH_SIZE = 100
    PROGRESS_METADATA_KEY = "insight_generation_progress".freeze

    def self.generate_all!(source: nil, progress: nil, memory_context: {})
      baseline = Aicoo::MemoryDiagnostics.snapshot
      Aicoo::MemoryDiagnostics.point("InsightGeneration::generate_all.entry", context: memory_context, baseline:)
      memory_context = Aicoo::MemoryDiagnostics.measure("InsightGeneration::memory_context", context: memory_context) do
        memory_context.to_h
      end
      Aicoo::MemoryDiagnostics.point(
        "InsightGeneration::progress_initialization",
        context: memory_context,
        baseline:,
        progress_present: progress.present?,
        progress_class: progress.class.name
      )
      return generate_all_without_run!(progress:, memory_context:) if source.blank?

      run = Aicoo::MemoryDiagnostics.measure("InsightGeneration::run_creation", context: memory_context) do
        AicooInsightGenerationRun.create!(source:, status: "running", started_at: Time.current)
      end
      Aicoo::MemoryDiagnostics.point("InsightGeneration::before_generate_all_without_run", context: memory_context.merge(insight_generation_run_id: run.id), baseline:)
      result = generate_all_without_run!(progress:, memory_context: memory_context.merge(insight_generation_run_id: run.id))
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

    def self.generate_all_without_run!(progress: nil, memory_context: {})
      baseline = Aicoo::MemoryDiagnostics.snapshot
      Aicoo::MemoryDiagnostics.point("InsightGeneration::generate_all_without_run.entry", context: memory_context, baseline:)
      summary = Result.new
      processed = 0
      batch_no = 0
      batch_size = insight_generation_batch_size
      resume_state = insight_generation_resume_state(memory_context)
      batch_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      batch_rss_before = Aicoo::MemoryDiagnostics.current_rss_mb
      business_scope = Aicoo::MemoryDiagnostics.measure("InsightGeneration::business_scope", context: memory_context) do
        Business.real_businesses.order(:id)
      end
      business_count = Aicoo::MemoryDiagnostics.measure("InsightGeneration::business_count", context: memory_context) do
        business_scope.count
      end
      last_business_id = business_scope.maximum(:id)
      Aicoo::MemoryDiagnostics.point("InsightGeneration::before_first_business", context: memory_context, baseline:, business_count:, batch_size:, resume_business_id: resume_state[:business_id], resume_position: resume_state[:current_position])
      business_scope.find_each do |business|
        next if resume_state[:business_id].present? && business.id < resume_state[:business_id].to_i

        offset = business.id == resume_state[:business_id].to_i ? resume_state[:current_position].to_i : 0
        processed += 1
        business_result = Aicoo::MemoryDiagnostics.measure(
          "InsightGeneration::BusinessInsightGenerator",
          context: memory_context.merge(business_id: business.id, business_name: business.name, processed:, batch_no: batch_no + 1, batch_size:, spec_offset: offset)
        ) do
          new(business:, memory_context:).call_batch(offset:, limit: batch_size - batch_no)
        end
        summary += business_result
        batch_no += business_result.processed_count

        progress_payload = insight_generation_progress_payload(
          memory_context:,
          business:,
          business_count:,
          current_position: offset + business_result.processed_count,
          total_count: business_result.total_count,
          processed_count: batch_no,
          batch_size:,
          batch_started_at:,
          batch_rss_before:,
          last_spec: business_result.last_spec,
          completed_business: business_result.completed?,
          completed_all: business_result.completed? && business.id == last_business_id
        )
        progress&.call(batch: progress_batch_for(batch_no), processed: batch_no, insight_generation_progress: progress_payload)
        compact_batch_memory!
        Aicoo::MemoryDiagnostics.point("InsightGeneration::batch.finish", context: memory_context.merge(progress_payload))

        return summary if batch_no >= batch_size

        resume_state = {}
      rescue StandardError => e
        Rails.logger.warn("[AicooInsight::Generator] business_id=#{business.id} failed: #{e.class}: #{e.message}")
        summary += Result.new(failed_count: 1, skipped: [ "#{business.name}: #{e.class}: #{e.message}" ])
        progress&.call(batch: progress_batch_for([ batch_no, 1 ].max), processed: batch_no)
      end

      progress&.call(
        batch: progress_batch_for(batch_no),
        processed: batch_no,
        insight_generation_progress: insight_generation_progress_payload(
          memory_context:,
          business: nil,
          business_count:,
          current_position: 0,
          total_count: 0,
          processed_count: batch_no,
          batch_size:,
          batch_started_at:,
          batch_rss_before:,
          last_spec: nil,
          completed_business: true,
          completed_all: true
        )
      )
      summary
    end

    def self.progress_batch_for(processed)
      return 0 if processed.to_i <= 0

      (processed.to_f / 25).ceil
    end

    def self.insight_generation_batch_size
      value = ENV["INSIGHT_GENERATION_BATCH_SIZE"].to_i
      value.positive? ? value : DEFAULT_BATCH_SIZE
    end

    def self.insight_generation_resume_state(memory_context)
      step_id = memory_context[:step_id] || memory_context["step_id"]
      previous_progress = AicooDailyRunStep
        .where(step_name: "insight_generation")
        .where.not(id: step_id)
        .order(updated_at: :desc)
        .limit(20)
        .lazy
        .map { |step| step.metadata.to_h[PROGRESS_METADATA_KEY].to_h }
        .find(&:present?)

      return {} unless previous_progress.to_h["status"] == "in_progress"

      {
        business_id: previous_progress["business_id"].presence&.to_i,
        current_position: previous_progress["current_position"].to_i
      }.compact
    rescue StandardError => e
      Rails.logger.warn("[AicooInsight::Generator] insight progress resume skipped: #{e.class}: #{e.message}")
      {}
    end

    def self.insight_generation_progress_payload(memory_context:, business:, business_count:, current_position:, total_count:, processed_count:, batch_size:, batch_started_at:, batch_rss_before:, last_spec:, completed_business:, completed_all:)
      rss_after = Aicoo::MemoryDiagnostics.current_rss_mb
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - batch_started_at) * 1000).round
      remaining_count = [ total_count.to_i - current_position.to_i, 0 ].max
      status = completed_all ? "complete" : "in_progress"

      {
        daily_run_id: memory_context[:daily_run_id] || memory_context["daily_run_id"],
        step_id: memory_context[:step_id] || memory_context["step_id"],
        business_id: business&.id,
        current_position:,
        total_count:,
        processed_count:,
        remaining_count:,
        last_spec:,
        updated_at: Time.current.iso8601,
        status:,
        completed_business:,
        batch_no: progress_batch_for(processed_count),
        batch_size:,
        business_count:,
        rss_before: batch_rss_before,
        rss_after:,
        rss_delta: rss_delta(batch_rss_before, rss_after),
        elapsed_ms:
      }.compact
    end

    def self.compact_batch_memory!
      ActiveRecord::Base.connection.clear_query_cache if ActiveRecord::Base.connected?
      GC.start(full_mark: false, immediate_sweep: false)
    rescue StandardError => e
      Rails.logger.debug("[AicooInsight::Generator] batch memory compact skipped: #{e.class}: #{e.message}")
    end

    def self.rss_delta(before, after)
      return if before.nil? || after.nil?

      (after.to_d - before.to_d).round(1).to_f
    end

    def initialize(business:, memory_context: {})
      @business = business
      @memory_context = memory_context.to_h
    end

    def call
      specs = collect_specs

      process_specs(specs)
    end

    def call_batch(offset:, limit:)
      specs = collect_specs
      return Result.new(skipped: [ no_insight_reason ], processed_count: 0, total_count: 0, completed: true) if specs.empty?

      batch_specs = specs.drop(offset.to_i).first(limit.to_i)
      result = process_specs(batch_specs, include_empty_reason: false)
      result.with_batch_progress(
        processed_count: batch_specs.size,
        total_count: specs.size,
        completed: offset.to_i + batch_specs.size >= specs.size,
        last_spec: batch_specs.last&.title
      )
    ensure
      specs = batch_specs = nil
    end

    def collect_specs
      Aicoo::MemoryDiagnostics.measure("InsightGeneration::SpecCollection", context: diagnostic_context) do
        [
          measured("InsightGeneration::CtrImprovementSpecs") { ctr_improvement_specs },
          measured("InsightGeneration::PositionImprovementSpecs") { position_improvement_specs },
          measured("InsightGeneration::RevenueImprovementSpecs") { revenue_improvement_specs },
          measured("InsightGeneration::NeglectAlertSpecs") { neglect_alert_specs },
          measured("InsightGeneration::GrowthExpansionSpecs") { growth_expansion_specs },
          measured("InsightGeneration::WithdrawalSpecs") { withdrawal_specs }
        ].flatten.compact
      end
    end

    def process_specs(specs, include_empty_reason: true)
      created = []
      skipped = []
      return Result.new(created:, skipped: include_empty_reason ? [ no_insight_reason ] : []) if specs.empty?

      specs.each do |spec|
        if legacy_article_generation_disabled?(spec)
          skipped << "#{business.name}: legacy_article_analyzer_skipped #{spec.title}"
          Rails.logger.info(
            "legacy_article_analyzer skipped business_id=#{business.id} source=ai_insight reason=new_analyzer_active"
          )
          next
        end

        decision = measured("InsightGeneration::BusinessPlaybookDecision", spec:) do
          spec.business.business_type_playbook.call(spec_attributes(spec))
        end
        if !decision.allowed
          skipped << "#{business.name}: #{decision.reason}"
        elsif measured("InsightGeneration::DuplicateCheck", spec:) { duplicate?(spec) }
          skipped << "#{business.name}: duplicate #{spec.title}"
        else
          created << measured("InsightGeneration::ActionCandidateGeneration", spec:) { create_action_candidate!(spec) }
        end
      end

      Result.new(created:, skipped:)
    ensure
      created = skipped = nil
    end

    private

    attr_reader :business, :memory_context

    def legacy_article_generation_disabled?(spec)
      return false unless Aicoo::ArticleAnalyzerRouting.article_action_type?(spec.action_type)

      routing = Aicoo::ArticleAnalyzerRouting.call(business:)
      routing.legacy_article_analyzer_skipped?
    end

    def measured(name, spec: nil, &block)
      Aicoo::MemoryDiagnostics.measure(name, context: diagnostic_context(spec:), &block)
    end

    def diagnostic_context(spec: nil)
      base = memory_context.merge(
        daily_run_id: memory_context[:daily_run_id] || memory_context["daily_run_id"],
        step_id: memory_context[:step_id] || memory_context["step_id"],
        step_name: memory_context[:step_name] || memory_context["step_name"],
        business_id: business.id,
        business_name: business.name
      ).compact
      return base unless spec

      base.merge(
        action_type: spec.action_type,
        spec_title: spec.title
      )
    end

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
        metadata: {
          "insight_rule" => insight_rule(spec),
          "insight_reason" => spec.reason,
          "business_type_playbook" => measured("InsightGeneration::BusinessPlaybookMetadata", spec:) do
            spec.business.business_type_playbook.call(spec_attributes(spec)).metadata
          end
        }
      )
    end

    def spec_attributes(spec)
      {
        title: spec.title,
        description: spec.description,
        action_type: spec.action_type,
        evaluation_reason: spec.reason,
        execution_prompt: spec.execution_prompt
      }
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
      scope = AicooDataSnapshot
        .where(source_type:)
        .where(captured_at: 45.days.ago..Time.current)

      conditions = [ "payload ->> 'business_id' = ?" ]
      values = [ business.id.to_s ]

      analytics_site_ids = AicooAnalyticsSite.where(business_id: business.id).select(:id)
      if analytics_site_ids.exists?
        conditions << "payload ->> 'analytics_site_id' IN (?)"
        values << analytics_site_ids.pluck(:id).map(&:to_s)
      end

      data_import_ids = DataImport.joins(:data_source)
                                  .where(data_sources: { business_id: business.id, source_type: })
                                  .select(:id)
      if data_import_ids.exists?
        conditions << "source_id IN (?)"
        values << data_import_ids.pluck(:id)
      end

      scope.where(conditions.join(" OR "), *values)
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

    def no_insight_reason
      [
        "#{business.name}: Insight生成条件に一致しません",
        "gsc_rows=#{gsc_rows.size}",
        "recent30_pageviews=#{recent_metric_total(:pageviews, 30)}",
        "current_month_profit=#{business.current_month_profit.to_i}",
        "recent7_clicks=#{metric_total(:clicks, 7.days.ago.to_date..Date.current)}",
        "recent7_pageviews=#{metric_total(:pageviews, 7.days.ago.to_date..Date.current)}",
        "条件: CTR低い高表示GSC / 5-20位GSC / PV多い低利益 / 放置損失 / 成長率30%以上 / 低反応撤退候補 のいずれにも未該当"
      ].join(" / ")
    end
  end
end
