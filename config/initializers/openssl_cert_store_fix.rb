# Workaround for a macOS dev quirk where Net::HTTP, without an explicit
# cert_store, hits OpenSSL's default-verify-paths in a way that triggers
# CRL enforcement and fails with "unable to get certificate CRL" on some
# chains (notably googleapis.com). The same CA bundle loaded via
# Store#set_default_paths works fine — so we set one when callers don't.
# Scoped to development; Linux production environments are unaffected.
# THIS IS ONLY A DEVELOPMENT WORKAROUND. Do not use or test in production.
if Rails.env.development?
  require "net/http"
  require "openssl"

  module NetHttpDefaultCertStorePatch
    def connect
      if use_ssl? && @cert_store.nil?
        store = OpenSSL::X509::Store.new
        store.set_default_paths
        @cert_store = store
      end
      super
    end
  end

  Net::HTTP.prepend(NetHttpDefaultCertStorePatch)
end
