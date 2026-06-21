class SerpAnalysesController < ApplicationController
  before_action :set_business

  def create
    upload = serp_params[:file]
    raw_text = upload.present? ? upload.read.force_encoding("UTF-8").scrub : serp_params[:raw_text]
    filename = upload.present? ? upload.original_filename : "manual_serp_#{Time.current.to_i}.txt"

    result = SerpAnalysisImportService.new(
      @business,
      keyword: serp_params[:keyword],
      raw_text:,
      filename:,
      location: serp_params[:location],
      device: serp_params[:device]
    ).call

    redirect_to @business, notice: "SERP analyzed '#{result.serp_analysis.keyword}' with competition score #{result.serp_analysis.competition_score}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @business, alert: "SERP analysis failed: #{e.record.errors.full_messages.to_sentence}"
  rescue ArgumentError => e
    redirect_to @business, alert: "SERP analysis failed: #{e.message}"
  end

  private

  def set_business
    @business = Business.find(params.expect(:business_id))
  end

  def serp_params
    params.expect(serp_analysis: [ :keyword, :location, :device, :raw_text, :file ])
  end
end
