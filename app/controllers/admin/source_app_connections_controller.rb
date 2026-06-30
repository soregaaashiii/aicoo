module Admin
  class SourceAppConnectionsController < ApplicationController
    def index
      SourceAppConnection.ensure_suelog_defaults!
      @connections = SourceAppConnection.joins(:business)
                                        .includes(:business, :source_app_diff_rules)
                                        .order("businesses.name", :source_app)
    end

    def edit
      @connection = SourceAppConnection.find(params[:id])
    end

    def update
      @connection = SourceAppConnection.find(params[:id])
      if @connection.update(connection_params)
        redirect_to admin_source_app_connections_path, notice: "Source App Connectionを保存しました"
      else
        flash.now[:alert] = @connection.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def connection_params
      params.require(:source_app_connection).permit(:name, :source_app, :connection_type, :enabled, :status)
    end
  end
end
