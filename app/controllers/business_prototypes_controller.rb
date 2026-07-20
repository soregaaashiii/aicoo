class BusinessPrototypesController < ApplicationController
  before_action :set_business
  before_action :set_prototype, only: %i[edit update destroy]

  def create
    prototype = @business.business_prototypes.create!(prototype_params.merge(analysis_status: "queued"))
    Aicoo::BusinessRegistrationAnalysisJob.perform_later(@business.id, prototype.id)
    redirect_to business_path(@business, anchor: "business-prototypes"),
                notice: "#{prototype.prototype_type_label}を追加し、解析を開始しました。"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to business_path(@business, anchor: "business-prototypes"),
                alert: "Prototypeを追加できませんでした: #{e.record.errors.full_messages.to_sentence}"
  end

  def edit
  end

  def update
    @prototype.update!(prototype_params.merge(analysis_status: "queued"))
    Aicoo::BusinessRegistrationAnalysisJob.perform_later(@business.id, @prototype.id)
    redirect_to business_path(@business, anchor: "business-prototypes"),
                notice: "#{@prototype.prototype_type_label}を更新し、再解析を開始しました。"
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = "Prototypeを更新できませんでした: #{e.record.errors.full_messages.to_sentence}"
    render :edit, status: :unprocessable_content
  end

  def destroy
    @prototype.destroy!
    redirect_to business_path(@business, anchor: "business-prototypes"),
                notice: "Prototypeを削除しました。"
  end

  private

  def set_business
    @business = Business.real_businesses.find(params[:business_id])
  end

  def set_prototype
    @prototype = @business.business_prototypes.find(params[:id])
  end

  def prototype_params
    params.expect(business_prototype: %i[prototype_type name location])
  end
end
