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

    attach_receipt_pdf if @invoice_data[:invoice_pdf].present?

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

  def cancellation_scheduled
    @user = params[:user]
    @period_end = params[:period_end]

    mail to: @user.email, subject: "thin.ly - Subscription Cancellation Scheduled"
  end

  def subscription_reactivated
    @user = params[:user]

    mail to: @user.email, subject: "thin.ly - Subscription Reactivated"
  end

  private

  ALLOWED_PDF_HOSTS = %w[pay.stripe.com invoice.stripe.com].freeze
  PDF_OPEN_TIMEOUT  = 5  # seconds
  PDF_READ_TIMEOUT  = 10 # seconds
  PDF_MAX_SIZE      = 5.megabytes

  def attach_receipt_pdf
    pdf_url = @invoice_data[:invoice_pdf]
    uri = URI.parse(pdf_url)

    unless uri.is_a?(URI::HTTPS) && ALLOWED_PDF_HOSTS.include?(uri.host)
      Rails.logger.warn("[SubscriptionMailer] Rejected non-Stripe PDF URL: #{uri.host}")
      return
    end

    pdf_data = uri.open(
      open_timeout: PDF_OPEN_TIMEOUT,
      read_timeout: PDF_READ_TIMEOUT
    ).read(PDF_MAX_SIZE)

    attachments["receipt.pdf"] = { mime_type: "application/pdf", content: pdf_data }
  rescue StandardError => e
    Rails.logger.error("[SubscriptionMailer] Failed to attach receipt PDF: #{e.message}")
    # Don't block sending the email if PDF download fails
  end
end
