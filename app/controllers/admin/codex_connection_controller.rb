module Admin
  class CodexConnectionController < ApplicationController
    def show
      @summary = Aicoo::CodexConnection::Summary.new(business_id: params[:business_id]).call
    end
  end
end
