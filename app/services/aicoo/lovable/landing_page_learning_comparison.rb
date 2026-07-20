module Aicoo
  module Lovable
    class LandingPageLearningComparison
      MIN_PAGEVIEWS = 20
      METRIC_KEYS = %w[
        cvr
        cta_rate
        form_submit_rate
        scroll_rate
        bounce_rate
        engagement_seconds
        gsc_clicks_per_day
        gsc_impressions_per_day
        roi
        confidence
      ].freeze

      Row = Data.define(:business, :run, :learning, :performance_score, :sample_adequate)
      Result = Data.define(
        :rows,
        :current,
        :best,
        :worst,
        :own_average,
        :category_average,
        :global_average,
        :benchmark,
        :benchmark_source,
        :improvement_success_rate,
        :version_trend
      )

      def initialize(business:, repository: VersionRepository.new(business:), learning_overrides: {})
        @business = business
        @repository = repository
        @learning_overrides = learning_overrides
      end

      def call
        own_rows = rows_for(business, repository.published_versions)
        current = own_rows.max_by { |row| published_at(row.run) }
        comparable_own = own_rows.reject { |row| current && row.run.id == current.run.id }.select(&:sample_adequate)
        category_rows = external_rows(category_businesses)
        global_rows = external_rows(Business.real_businesses.where.not(id: business.id))
        own_average = averages(comparable_own)
        category_average = averages(category_rows.select(&:sample_adequate))
        global_average = averages(global_rows.select(&:sample_adequate))
        benchmark, benchmark_source = select_benchmark(own_average, category_average, global_average)

        Result.new(
          rows: own_rows,
          current:,
          best: ranked_rows(own_rows).last,
          worst: ranked_rows(own_rows).first,
          own_average:,
          category_average:,
          global_average:,
          benchmark:,
          benchmark_source:,
          improvement_success_rate: improvement_success_rate(own_rows),
          version_trend: version_trend(own_rows)
        )
      end

      private

      attr_reader :business, :repository, :learning_overrides

      def category_businesses
        scope = Business.real_businesses.where.not(id: business.id)
        business.category.present? ? scope.where(category: business.category) : scope.where(business_type: business.business_type)
      end

      def external_rows(businesses)
        businesses.flat_map do |other_business|
          rows_for(other_business, VersionRepository.new(business: other_business).published_versions)
        end
      end

      def rows_for(owner, runs)
        runs.map do |run|
          learning = learning_overrides[run.id] || run.metadata.to_h["learning"].presence || LearningSummary.new(business: owner, generation_run: run).call
          Row.new(
            business: owner,
            run:,
            learning: learning.deep_stringify_keys,
            performance_score: performance_score(learning),
            sample_adequate: learning["pageviews"].to_i >= MIN_PAGEVIEWS
          )
        end
      end

      def ranked_rows(rows)
        rows.select(&:sample_adequate).sort_by { |row| [ row.performance_score, published_at(row.run) ] }
      end

      def performance_score(learning)
        cvr = learning["cvr"].to_f
        confidence = learning["confidence"].to_f
        roi = learning["roi"]
        roi_score = roi.nil? ? 0.0 : ((roi.to_f + 1.0).clamp(0.0, 5.0) / 5.0)
        ((cvr.clamp(0.0, 0.2) / 0.2 * 50) + (roi_score * 30) + (confidence * 20)).round(2)
      end

      def averages(rows)
        return {} if rows.empty?

        metrics = METRIC_KEYS.to_h do |key|
          values = rows.filter_map { |row| metric_value(row.learning, key) }
          [ key, values.empty? ? nil : (values.sum / values.length).round(4) ]
        end
        metrics.merge("sample_count" => rows.length)
      end

      def metric_value(learning, key)
        value = case key
        when "bounce_rate", "engagement_seconds"
          learning.dig("ga4", key)
        when "gsc_clicks_per_day", "gsc_impressions_per_day"
          learning.dig("metrics", key)
        else
          learning[key]
        end
        value.to_f if value.present?
      end

      def select_benchmark(*benchmarks)
        labels = %w[own_versions same_category all_businesses]
        benchmarks.each_with_index do |benchmark, index|
          return [ benchmark, labels[index] ] if benchmark["sample_count"].to_i.positive?
        end
        [ {}, "unavailable" ]
      end

      def improvement_success_rate(rows)
        ordered = rows.select(&:sample_adequate).sort_by { |row| published_at(row.run) }
        comparisons = ordered.each_cons(2).map { |before, after| after.performance_score > before.performance_score }
        return if comparisons.empty?

        (comparisons.count(true).to_d / comparisons.length).round(4).to_f
      end

      def version_trend(rows)
        ordered = rows.select(&:sample_adequate).sort_by { |row| published_at(row.run) }
        return "insufficient_history" if ordered.length < 2

        delta = ordered.last.performance_score - ordered[-2].performance_score
        return "improving" if delta.positive?
        return "declining" if delta.negative?

        "stable"
      end

      def published_at(run)
        Time.zone.parse(run.metadata.to_h.dig("publication", "published_at").to_s)
      rescue ArgumentError, TypeError
        run.created_at
      end
    end
  end
end
