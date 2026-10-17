class AicooSessionsController < ApplicationController
  layout false

  def new
    @return_to = safe_return_to(params[:return_to])
  end

  def create
    unless aicoo_management_credentials_configured?
      render plain: "AICOO management access is not configured.", status: :forbidden
      return
    end

    @return_to = safe_return_to(params[:return_to])
    if aicoo_management_credentials_match?(params[:username], params[:password])
      reset_session
      session[:aicoo_management_credential_digest] = aicoo_management_credential_digest
      redirect_to @return_to
    else
      flash.now[:alert] = "ユーザー名またはパスワードが正しくありません。"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to aicoo_login_path
  end

  private

  def safe_return_to(value)
    candidate = value.to_s
    return aicoo_setting_path unless candidate.match?(%r{\A/(?!/)})
    return aicoo_setting_path if candidate.include?("\\")

    candidate
  end
end
