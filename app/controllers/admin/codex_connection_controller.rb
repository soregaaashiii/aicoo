module Admin
  class CodexConnectionController < ApplicationController
    def show
      @summary = Aicoo::CodexConnectionSummary.new.call
    end
  end
end
