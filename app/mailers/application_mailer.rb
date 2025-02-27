class ApplicationMailer < ActionMailer::Base
  default from: "notifications@thin.ly"
  layout "mailer"
end
