require "open-uri"

class SubscriptionMailer < ApplicationMailer
  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.subscription_mailer.payment_failed.subject
  #
  def payment_failed
    @user = params[:user]

    mail to: @user.email, subject: "thin.ly - Payment Attempt Failed"
  end

  def payment_completed
    @user = params[:user]
    @invoice_data = params[:invoice_data] || {}

    mail to: @user.email, subject: "Welcome to thin.ly - Payment Confirmed"
  end

  def payment_successful
    @user = params[:user]
    @invoice_data = params[:invoice_data] || {}

    attach_receipt_pdf if @invoice_data[:invoice_pdf].present?

    mail to: @user.email, subject: "thin.ly - Payment Receipt - Thank You"
  end

  def payment_action_required
    @user = params[:user]
    @hosted_invoice_url = params[:url]

    mail to: @user.email, subject: "thin.ly - Action Required to Complete Payment"
  end

  def subscription_canceled
    @user = params[:user]

    mail to: @user.email, subject: "thin.ly - Subscription Canceled"
  end

  private

  def attach_receipt_pdf
    pdf_url = @invoice_data[:invoice_pdf]
    pdf_data = URI.open(pdf_url).read # rubocop:disable Security/Open — Stripe-hosted URL only
    attachments["receipt.pdf"] = { mime_type: "application/pdf", content: pdf_data }
  rescue StandardError => e
    Rails.logger.error("[SubscriptionMailer] Failed to attach receipt PDF: #{e.message}")
    # Don't block sending the email if PDF download fails
  end
end
