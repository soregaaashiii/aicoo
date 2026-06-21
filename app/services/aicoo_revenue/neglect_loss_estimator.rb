module AicooRevenue
  class NeglectLossEstimator
    STALE_GRACE_DAYS = 14

    Result = Data.define(:estimated_neglect_loss_90d_yen, :auto_generated, :reasons)

    def initialize(record)
      @record = record
      @reasons = []
    end

    def call
      loss = [
        stale_loss,
        ga4_loss,
        gsc_loss,
        landing_page_loss
      ].sum.round

      Result.new(
        estimated_neglect_loss_90d_yen: [ loss, 0 ].max,
        auto_generated: loss.positive?,
        reasons:
      )
    end

    def estimate_and_store!
      result = call
      return result unless record.respond_to?(:estimated_neglect_loss_90d_yen)

      record.update_columns(
        estimated_neglect_loss_90d_yen: result.estimated_neglect_loss_90d_yen,
        neglect_loss_auto_generated: result.auto_generated
      )
      result
    end

    private

    attr_reader :record, :reasons

    def base_value
      profit =
        if record.respond_to?(:expected_90d_profit_yen)
          record.expected_90d_profit_yen
        elsif record.respond_to?(:expected_profit_yen)
          record.expected_profit_yen
        end

      probability =
        if record.respond_to?(:success_probability)
          normalize_probability(record.success_probability)
        else
          1
        end

      profit.to_d * probability.to_d
    end

    def stale_loss
      days = neglected_days
      return 0 if days <= STALE_GRACE_DAYS || base_value.zero?

      risk_ratio = [ (days - STALE_GRACE_DAYS).to_d / 90, 1 ].min
      loss = base_value * risk_ratio * 0.25
      reasons << "更新停止#{days}日による劣化リスク" if loss.positive?
      loss
    end

    def ga4_loss
      previous, latest = paired_snapshots("ga4")
      return 0 unless previous && latest

      latest_views = metric(latest, :page_views)
      previous_views = metric(previous, :page_views)
      decline_loss(previous_views, latest_views, weight: 0.4, reason: "GA4 PV減少")
    end

    def gsc_loss
      previous, latest = paired_snapshots("gsc")
      return 0 unless previous && latest

      clicks_loss = decline_loss(metric(previous, :clicks), metric(latest, :clicks), weight: 0.5, reason: "GSCクリック減少")
      ctr_loss = decline_loss(metric(previous, :ctr), metric(latest, :ctr), weight: 0.25, reason: "GSC CTR低下")
      position_loss = position_drop_loss(metric(previous, :position), metric(latest, :position))

      clicks_loss + ctr_loss + position_loss
    end

    def landing_page_loss
      previous, latest = paired_snapshots("landing_page")
      return 0 unless previous && latest

      pv_loss = decline_loss(metric(previous, :pv), metric(latest, :pv), weight: 0.3, reason: "LP PV減少")
      signup_loss = decline_loss(metric(previous, :signup_rate), metric(latest, :signup_rate), weight: 0.3, reason: "LP Signup率低下")

      pv_loss + signup_loss
    end

    def paired_snapshots(source_type)
      snapshots = relevant_snapshots(source_type).limit(2).to_a
      return [] if snapshots.size < 2

      [ snapshots.second, snapshots.first ]
    end

    def relevant_snapshots(source_type)
      scope = AicooDataSnapshot.where(source_type:).recent

      case source_type
      when "ga4", "gsc"
        business_id ? scope.where("payload ->> 'business_id' = ?", business_id.to_s) : scope.none
      when "landing_page"
        landing_page_id ? scope.where(source_id: landing_page_id) : scope.none
      else
        scope.none
      end
    end

    def business_id
      return record.business_id if record.respond_to?(:business_id)

      nil
    end

    def landing_page_id
      return record.aicoo_lab_landing_page&.id if record.respond_to?(:aicoo_lab_landing_page)

      nil
    end

    def decline_loss(previous_value, latest_value, weight:, reason:)
      previous_value = previous_value.to_d
      latest_value = latest_value.to_d
      return 0 unless previous_value.positive? && latest_value < previous_value && base_value.positive?

      decline_ratio = (previous_value - latest_value) / previous_value
      loss = base_value * decline_ratio * weight
      reasons << "#{reason} #{(decline_ratio * 100).round(1)}%" if loss.positive?
      loss
    end

    def position_drop_loss(previous_position, latest_position)
      previous_position = previous_position.to_d
      latest_position = latest_position.to_d
      return 0 unless previous_position.positive? && latest_position > previous_position && base_value.positive?

      drop_ratio = [ (latest_position - previous_position) / 10, 1 ].min
      loss = base_value * drop_ratio * 0.25
      reasons << "GSC順位下落 #{previous_position.to_f.round(1)}→#{latest_position.to_f.round(1)}" if loss.positive?
      loss
    end

    def metric(snapshot, key)
      payload = snapshot.payload || {}
      metrics = payload["metrics"] || {}
      value = metrics[key.to_s] || payload[key.to_s]
      value.to_d
    end

    def normalize_probability(probability)
      value = probability.to_d
      value > 1 ? value / 100 : value
    end

    def neglected_days
      ((Time.current - record.updated_at) / 1.day).floor
    end
  end
end
