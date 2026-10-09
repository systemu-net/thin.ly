module Api
  module Levelcode
    module V1
      # Whether the editor has a web edition, and where. The account page asks, to decide whether to
      # offer "Open in browser" and where that goes — the address is configuration, never a constant
      # of the page (LEVELCODE_WEB_EDITOR_ORIGINS / _URL, read by Levelcode::EditorCallback).
      #
      # Public and the same for everyone, so a shared cache may hold it: no auth, no cookie, and a
      # short max-age so a change of setting reaches the page within minutes of the restart.
      class WebEditorController < BaseController
        skip_before_action :authenticate_levelcode!, only: %i[show]

        # GET /api/levelcode/v1/web_editor
        #   -> { enabled: true,  url: "https://editor.levelcode.ai" }
        #   -> { enabled: false, url: null }
        def show
          rule = ::Levelcode::EditorCallback.current
          expires_in 5.minutes, public: true
          render json: { enabled: rule.web_enabled?, url: rule.web_url }, status: :ok
        end
      end
    end
  end
end
