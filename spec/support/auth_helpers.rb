# spec/support/auth_helpers.rb
module AuthHelpers
  def auth_headers(user)
    token = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
    { 'Authorization' => "Bearer #{token}" }
  end

  # Run an example on a server told to take further editor schemes — what
  # LEVELCODE_EXTRA_EDITOR_SCHEMES would set (Levelcode::EditorCallback).
  def with_extra_editor_schemes(list)
    allow(Levelcode::EditorCallback).to receive(:current).and_return(Levelcode::EditorCallback.new(extra_schemes: list))
  end

  # Run an example on a server told of a web edition of the editor — what LEVELCODE_WEB_EDITOR_ORIGINS
  # (and, when given, LEVELCODE_WEB_EDITOR_URL) would set (Levelcode::EditorCallback). The callback
  # gates, CORS and the config endpoint all read the same rule, so this is the one place a spec says so.
  #
  # extension_hosts: what LEVELCODE_WEB_EXTENSION_HOST_ORIGINS would set — the origins the editor's
  # extension host runs on, for CORS only.
  def with_web_editor(origins, url: "", extra_schemes: "", extension_hosts: "")
    allow(Levelcode::EditorCallback).to receive(:current).and_return(
      Levelcode::EditorCallback.new(
        extra_schemes: extra_schemes, web_origins: origins, web_url: url, extension_host_origins: extension_hosts
      )
    )
  end
end
