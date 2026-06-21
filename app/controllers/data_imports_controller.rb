require "csv"

class DataImportsController < ApplicationController
  before_action :set_business

  def create
    upload = data_import_params[:file]
    return redirect_to @business, alert: "Upload a CSV or TXT file." if upload.blank?

    raw_text = upload.read.force_encoding("UTF-8").scrub
    data_source = find_or_create_data_source
    data_source.data_imports.create!(
      filename: upload.original_filename,
      content_type: upload.content_type,
      row_count: count_rows(raw_text, upload.original_filename),
      raw_text:,
      processed_text: processed_text(raw_text),
      imported_at: Time.current
    )

    redirect_to @business, notice: "Data import uploaded for #{@business.name}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @business, alert: "Data upload failed: #{e.record.errors.full_messages.to_sentence}"
  rescue CSV::MalformedCSVError => e
    redirect_to @business, alert: "CSV could not be parsed: #{e.message}"
  end

  private

  def set_business
    @business = Business.find(params.expect(:business_id))
  end

  def data_import_params
    params.expect(data_import: [ :name, :source_type, :status, :notes, :file ])
  end

  def find_or_create_data_source
    @business.data_sources.find_or_create_by!(
      name: data_import_params[:name].presence || data_import_params[:source_type].to_s.humanize,
      source_type: data_import_params[:source_type].presence || "custom"
    ) do |data_source|
      data_source.status = data_import_params[:status].presence || "active"
      data_source.notes = data_import_params[:notes]
    end
  end

  def count_rows(raw_text, filename)
    return raw_text.lines.count unless File.extname(filename).casecmp(".csv").zero?

    rows = CSV.parse(raw_text, headers: true)
    rows.size
  end

  def processed_text(raw_text)
    raw_text.truncate(20_000)
  end
end
