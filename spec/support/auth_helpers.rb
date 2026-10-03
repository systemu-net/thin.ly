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
end
