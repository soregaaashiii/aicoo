module LovableLandingPagesHelper
  PIPELINE_DIAGNOSIS_SETTINGS_LINKS = {
    github: {
      label: "GitHub設定を開く",
      url: "https://github.com/settings/personal-access-tokens"
    },
    cloudflare: {
      label: "Cloudflareを開く",
      url: "https://dash.cloudflare.com/"
    },
    ga4: {
      label: "GA4を開く",
      url: "https://analytics.google.com/analytics/web/"
    },
    gsc: {
      label: "Search Consoleを開く",
      url: "https://search.google.com/search-console"
    }
  }.freeze

  def pipeline_diagnosis_settings_link(component, landing_page:)
    return unless component.actionable?

    if component.key == :webhook
      repository = Aicoo::Lovable::GithubRepositoryIdentity.normalize(
        component.details["Repository"].presence || landing_page&.landing_page_repository_url
      )
      return {
        label: "Webhook設定を開く",
        url: repository.present? ? "https://github.com/#{repository}/settings/hooks" : "https://github.com/settings/repositories"
      }
    end

    PIPELINE_DIAGNOSIS_SETTINGS_LINKS[component.key]
  end
end
