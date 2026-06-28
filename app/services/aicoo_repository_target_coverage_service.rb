class AicooRepositoryTargetCoverageService
  STATUS_LABELS = {
    "configured" => "✅ configured",
    "incomplete" => "⚠ incomplete",
    "missing" => "❌ missing",
    "inactive" => "⏸ inactive"
  }.freeze

  Result = Data.define(
    :total_businesses,
    :configured_businesses,
    :missing_profile_businesses,
    :incomplete_profile_businesses,
    :active_profile_businesses,
    :inactive_profile_businesses,
    :coverage_rate,
    :items
  ) do
    def problem_items
      items.reject { |item| item.status == "configured" }
    end
  end

  Item = Data.define(:business, :profile, :status, :missing_fields) do
    def status_label
      STATUS_LABELS.fetch(status)
    end

    def missing_fields_label
      return "Execution Profile未作成" if status == "missing"
      return "無効化されています" if status == "inactive"
      return "-" if missing_fields.empty?

      missing_fields.join(", ")
    end
  end

  def call
    businesses = Business.real_businesses.includes(:business_execution_profile).order(:name)
    items = businesses.map { |business| build_item(business) }
    total = items.size
    configured = items.count { |item| item.status == "configured" }
    active_profiles = items.count { |item| item.profile&.active? }

    Result.new(
      total_businesses: total,
      configured_businesses: configured,
      missing_profile_businesses: items.count { |item| item.status == "missing" },
      incomplete_profile_businesses: items.count { |item| item.status == "incomplete" },
      active_profile_businesses: active_profiles,
      inactive_profile_businesses: items.count { |item| item.status == "inactive" },
      coverage_rate: total.positive? ? ((configured.to_d / total) * 100).round(1) : 0.to_d,
      items:
    )
  end

  private

  def build_item(business)
    profile = business.business_execution_profile
    return Item.new(business:, profile: nil, status: "missing", missing_fields: []) unless profile

    Item.new(
      business:,
      profile:,
      status: profile.coverage_status,
      missing_fields: profile.missing_required_fields
    )
  end
end
