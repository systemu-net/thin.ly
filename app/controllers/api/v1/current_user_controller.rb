
module Api
  module V1
    class CurrentUserController < ApplicationController
      before_action :authenticate_user!

      def index
        render :index, status: :ok
      end
    end
  end
end
