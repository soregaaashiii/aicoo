class BusinessesController < ApplicationController
  before_action :set_business, only: %i[ show edit update destroy generate_ai_candidates import_gsc ]

  # GET /businesses or /businesses.json
  def index
    @businesses = Business.includes(:business_execution_profile).order(:name)
  end

  # GET /businesses/1 or /businesses/1.json
  def show
    @action_candidates = @business.action_candidates.by_recommendation
    @data_sources = @business.data_sources.includes(:data_imports).order(:name)
    @recent_data_imports = @business.data_imports.includes(:data_source).recent.limit(5)
    @recent_serp_analyses = @business.serp_analyses.order(analyzed_at: :desc).limit(10)
  end

  # GET /businesses/new
  def new
    @business = Business.new(status: "idea")
  end

  # GET /businesses/1/edit
  def edit
  end

  # POST /businesses or /businesses.json
  def create
    @business = Business.new(business_params)

    respond_to do |format|
      if @business.save
        format.html { redirect_to @business, notice: "Business was successfully created." }
        format.json { render :show, status: :created, location: @business }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @business.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /businesses/1 or /businesses/1.json
  def update
    respond_to do |format|
      if @business.update(business_params)
        format.html { redirect_to @business, notice: "Business was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @business }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @business.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /businesses/1 or /businesses/1.json
  def destroy
    @business.destroy!

    respond_to do |format|
      format.html { redirect_to businesses_path, notice: "Business was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  def generate_ai_candidates
    result = AiActionGeneratorService.new(@business, action_count: ai_action_count).call

    redirect_to action_candidates_path, notice: "AI generated #{result.action_candidates.size} action candidates for #{@business.name}."
  rescue OpenaiResponsesClient::MissingApiKeyError => e
    redirect_to @business, alert: e.message
  rescue OpenaiResponsesClient::Error, ActiveRecord::RecordInvalid => e
    redirect_to @business, alert: "AI candidate generation failed: #{e.message}"
  end

  def import_gsc
    result = GscImportService.new(@business).call

    redirect_to @business, notice: "GSC imported #{result.data_import.row_count} query rows for #{@business.name}."
  rescue GoogleOauthClient::MissingCredentialsError, GoogleOauthClient::Error, GscSearchAnalyticsClient::Error => e
    redirect_to @business, alert: "GSC import failed: #{e.message}"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @business, alert: "GSC import failed: #{e.record.errors.full_messages.to_sentence}"
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_business
      @business = Business.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def business_params
      params.expect(business: [ :name, :description, :status, :gsc_site_url ])
    end

    def ai_action_count
      count = params[:action_count].to_i
      [ 3, 5, 10 ].include?(count) ? count : 5
    end
end
