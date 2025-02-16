
module Api
  module V1
    class CurrentUserController < ApplicationController
      before_action :authenticate_user!

      def index
        @plan = current_user.plan
        @features = %i[links qr_codes pages].map do |feature|
          {
            name: feature,
            limit: @plan.send(feature),
            used: @plan.send("#{feature}_created_within_last_30_days")
          }
        end
        render :index, status: :ok
      end
    end
  end
end
