require "uri"

module AicooAnalytics
  class SiteAutolinker
    Result = Data.define(:created_count, :updated_count, :skipped_count, :warnings)

    def initialize(base_url: nil)
      @base_url = base_url
      @created_count = 0
      @updated_count = 0
      @skipped_count = 0
      @warnings = []
    end

    def call
      link_businesses
      link_experiments
      link_landing_pages
      result
    end

    def link!(record)
      public_url = public_url_for(record)
      unless public_url
        @skipped_count += 1
        @warnings << "#{record_label(record)}: 公開URL未設定"
        return result
      end

      upsert_site!(record, public_url)
      result
    end

    private

    attr_reader :base_url

    def link_businesses
      Business.find_each { |business| link!(business) }
    end

    def link_experiments
      AicooLabExperiment.where.not(public_url: [ nil, "" ]).find_each { |experiment| link!(experiment) }
    end

    def link_landing_pages
      AicooLabLandingPage.publish_due!
      AicooLabLandingPage.publicly_available.find_each { |landing_page| link!(landing_page) }
    end

    def upsert_site!(record, public_url)
      uri = URI.parse(public_url)
      domain = uri.host
      site = find_existing_site(record, public_url, domain) || AicooAnalyticsSite.new
      was_new = site.new_record?
      business = business_for(record)

      site.assign_attributes(
        name: site_name_for(record, business),
        business: business || site.business,
        public_url:,
        domain: domain.presence || site.domain,
        enabled: true,
        authentication_mode: "shared",
        auto_created: true,
        autolink_source_type: record.class.name,
        autolink_source_id: record.id,
        notes: autolink_note(record)
      )
      site.save!
      was_new ? @created_count += 1 : @updated_count += 1
    rescue URI::InvalidURIError
      @skipped_count += 1
      @warnings << "#{record_label(record)}: 公開URLが不正です"
    end

    def find_existing_site(record, public_url, domain)
      business = business_for(record)
      source_match = AicooAnalyticsSite.find_by(autolink_source_type: record.class.name, autolink_source_id: record.id)
      return source_match if source_match

      AicooAnalyticsSite.find_by(public_url:) ||
        (domain.present? ? AicooAnalyticsSite.find_by(domain:) : nil) ||
        (business ? AicooAnalyticsSite.find_by(business:) : nil)
    end

    def public_url_for(record)
      case record
      when Business
        value_from(record, :site_url) || value_from(record, :public_url)
      when AicooLabExperiment
        record.public_url.presence
      when AicooLabLandingPage
        value_from(record, :published_url) ||
          value_from(record, :public_url) ||
          public_landing_page_url(record)
      end
    end

    def public_landing_page_url(landing_page)
      return nil if landing_page.published_slug.blank?

      "#{resolved_base_url}/lp/#{landing_page.published_slug}" if resolved_base_url.present?
    end

    def resolved_base_url
      @resolved_base_url ||= begin
        value = base_url.presence || ENV["AICOO_PUBLIC_BASE_URL"].presence || ENV["RENDER_EXTERNAL_URL"].presence
        value ||= default_url_base
        value&.delete_suffix("/")
      end
    end

    def default_url_base
      options = Rails.application.routes.default_url_options
      host = options[:host].presence
      return nil if host.blank?

      protocol = options[:protocol].presence || "http"
      port = options[:port].presence
      port_part = port ? ":#{port}" : ""
      "#{protocol}://#{host}#{port_part}"
    end

    def business_for(record)
      case record
      when Business
        record
      when AicooLabExperiment
        nil
      when AicooLabLandingPage
        nil
      end
    end

    def site_name_for(record, business)
      business&.name || value_from(record, :title) || value_from(record, :headline) || record.class.model_name.human
    end

    def autolink_note(record)
      "AICOO内の#{record.class.name}から自動作成"
    end

    def record_label(record)
      site_name_for(record, business_for(record))
    end

    def value_from(record, method_name)
      record.public_send(method_name).presence if record.respond_to?(method_name)
    end

    def result
      Result.new(
        created_count: @created_count,
        updated_count: @updated_count,
        skipped_count: @skipped_count,
        warnings: @warnings
      )
    end
  end
end
