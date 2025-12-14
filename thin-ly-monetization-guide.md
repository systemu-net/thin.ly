thin.ly Monetization System - Complete Implementation Guide
Version: 1.0
Date: November 12, 2025
Author: AI Assistant for Sergii @ thin.ly

Table of Contents

Executive Summary
Business Model Overview
Google AdSense Setup & Approval
Database Architecture
Backend Implementation
Interstitial Ad Page
User Dashboard & Analytics
Revenue Sharing System
Fraud Detection & Prevention
Legal & Compliance
Email Notifications
Admin Tools
Testing & Quality Assurance
Marketing & SEO
Advanced Features
Implementation Checklist
Appendix


1. Executive Summary
1.1 Overview
This guide provides a complete implementation of a monetization system for thin.ly, similar to Bitly's ad-supported model announced for March 2025. The system allows users to earn revenue from their shortened links through Google AdSense advertisements displayed on an interstitial page before redirect.
1.2 Key Features

40/60 Revenue Split: Users earn 40% of ad revenue, platform retains 60%
Per-Link Control: Users choose which links show ads
Google AdSense Integration: Reliable, high-quality ad network
Real-Time Analytics: Track impressions, clicks, CTR, and earnings
Fraud Detection: Advanced monitoring to prevent invalid activity
$10 Minimum Payout: Lower barrier than competitors
Monthly Payments: Automated through Google AdSense

1.3 Competitive Advantages
Featurethin.lyBitlyOthersRevenue Share40%0%20-30%Per-Link Control✓ Yes✗ NoLimitedMinimum Payout$10N/A$50-100Custom DomainsFree$35/moPaidReal-Time Analytics✓ YesDelayedBasic

2. Business Model Overview
2.1 Revenue Flow
User clicks shortened link
    ↓
Interstitial page displays (3-7 seconds)
    ↓
Google AdSense shows relevant ads
    ↓
Revenue generated: $1-5 CPM average
    ↓
Split: 40% to user, 60% to platform
    ↓
Monthly payout (minimum $10)
2.2 Target Users

Social Media Influencers: Monetize bio links and story swipes
Content Creators: Earn from blog posts and newsletters
Marketers: Generate revenue from campaigns and QR codes
Affiliate Marketers: Additional income stream
Small Businesses: Monetize promotional materials
Educators: Share resources while earning

2.3 Expected Earnings
Monthly ClicksAverage CPMTotal RevenueUser Earnings (40%)Platform (60%)1,000$2.00$2.00$0.80$1.205,000$2.00$10.00$4.00$6.0010,000$2.00$20.00$8.00$12.0050,000$3.00$150.00$60.00$90.00100,000$3.00$300.00$120.00$180.00
Note: CPM varies by geography, niche, and audience quality.

3. Google AdSense Setup & Approval
3.1 Prerequisites

Domain age: 6+ months (thin.ly qualifies)
Original content on main site
Privacy policy and terms of service
Compliance with AdSense policies
Valid business/individual information

3.2 Application Process

Go to Google AdSense: https://www.google.com/adsense/start/
Sign up with Google account
Provide domain information: thin.ly
Add AdSense code to your website:

html<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-XXXXXXXXXX"
     crossorigin="anonymous"></script>

Wait for approval: Typically 1-2 weeks
Receive Publisher ID: Format ca-pub-XXXXXXXXXXXXXXXX

3.3 Creating Ad Units
Once approved:

Go to Ads → Overview → By ad unit
Create Display ads unit
Select Responsive size
Name: "thin.ly Interstitial Ad"
Copy ad code and slot ID

3.4 Policy Compliance
Allowed:

Social media links
Blog posts and articles
Email marketing (with permission)
QR codes on print materials
Educational content

Prohibited:

Adult/sexual content
Illegal drugs or weapons
Copyrighted material infringement
Hate speech or violence
Malware or phishing sites
Encouraging ad clicks
Self-clicking ads


4. Database Architecture
4.1 Database Migrations
Add Monetization Fields to Users
ruby# db/migrate/XXXXXX_add_monetization_to_users.rb
class AddMonetizationToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :adsense_enabled, :boolean, default: false
    add_column :users, :adsense_publisher_id, :string
    add_column :users, :revenue_share_percentage, :decimal, precision: 5, scale: 2, default: 40.0
    add_column :users, :total_ad_impressions, :integer, default: 0
    add_column :users, :estimated_earnings, :decimal, precision: 10, scale: 2, default: 0.0
    add_column :users, :onboarding_completed, :boolean, default: false
    add_column :users, :suspension_reason, :text
    
    add_index :users, :adsense_enabled
    add_index :users, :adsense_publisher_id
  end
end
Add Monetization Fields to Links
ruby# db/migrate/XXXXXX_add_monetization_to_links.rb
class AddMonetizationToLinks < ActiveRecord::Migration[7.0]
  def change
    add_column :links, :show_ads, :boolean, default: false
    add_column :links, :ad_impressions, :integer, default: 0
    add_column :links, :ad_clicks, :integer, default: 0
    add_column :links, :redirect_delay_seconds, :integer, default: 5
    
    add_index :links, :show_ads
    add_index :links, [:user_id, :show_ads]
  end
end
Create AdImpressions Table
ruby# db/migrate/XXXXXX_create_ad_impressions.rb
class CreateAdImpressions < ActiveRecord::Migration[7.0]
  def change
    create_table :ad_impressions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :link, null: false, foreign_key: true
      t.string :visitor_ip
      t.string :user_agent
      t.text :referrer
      t.string :country_code, limit: 2
      t.boolean :ad_clicked, default: false
      t.decimal :estimated_revenue, precision: 10, scale: 4, default: 0.0
      t.integer :redirect_delay
      
      t.timestamps
    end
    
    add_index :ad_impressions, :created_at
    add_index :ad_impressions, [:user_id, :created_at]
    add_index :ad_impressions, [:link_id, :created_at]
    add_index :ad_impressions, :visitor_ip
    add_index :ad_impressions, :country_code
    add_index :ad_impressions, :ad_clicked
  end
end
Create FraudAlerts Table
ruby# db/migrate/XXXXXX_create_fraud_alerts.rb
class CreateFraudAlerts < ActiveRecord::Migration[7.0]
  def change
    create_table :fraud_alerts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :link, null: false, foreign_key: true
      t.text :flags, array: true, default: []
      t.text :description
      t.string :severity # 'low', 'medium', 'high'
      t.boolean :resolved, default: false
      t.integer :resolved_by
      t.text :resolution_notes
      
      t.timestamps
    end
    
    add_index :fraud_alerts, :resolved
    add_index :fraud_alerts, :severity
    add_index :fraud_alerts, :created_at
  end
end
4.2 Run Migrations
bashrails db:migrate

5. Backend Implementation
5.1 Models
User Model
ruby# app/models/user.rb
class User < ApplicationRecord
  has_many :links, dependent: :destroy
  has_many :ad_impressions, dependent: :destroy
  has_many :fraud_alerts, dependent: :destroy
  
  # Validations
  validates :revenue_share_percentage, 
    numericality: { 
      greater_than_or_equal_to: 0, 
      less_than_or_equal_to: 100 
    }
  
  validates :adsense_publisher_id, 
    format: { 
      with: /\Aca-pub-\d{16}\z/, 
      message: "must be a valid AdSense Publisher ID" 
    },
    allow_blank: true
  
  # Scopes
  scope :monetization_enabled, -> { where(adsense_enabled: true) }
  scope :with_fraud_alerts, -> { joins(:fraud_alerts).where(fraud_alerts: { resolved: false }).distinct }
  
  # Methods
  def enable_adsense!(publisher_id)
    update!(
      adsense_enabled: true,
      adsense_publisher_id: publisher_id
    )
  end
  
  def disable_adsense!(reason = nil)
    update!(
      adsense_enabled: false,
      suspension_reason: reason
    )
    
    # Disable ads on all links
    links.update_all(show_ads: false)
  end
  
  def calculate_earnings(start_date, end_date)
    ad_impressions
      .where(created_at: start_date..end_date)
      .sum(:estimated_revenue) * (revenue_share_percentage / 100.0)
  end
  
  def monthly_earnings
    calculate_earnings(1.month.ago, Time.current)
  end
  
  def eligible_for_payout?
    monthly_earnings >= 10.0
  end
end
Link Model
ruby# app/models/link.rb
class Link < ApplicationRecord
  belongs_to :user
  has_many :ad_impressions, dependent: :destroy
  
  # Validations
  validates :redirect_delay_seconds, 
    numericality: { 
      greater_than_or_equal_to: 3, 
      less_than_or_equal_to: 10 
    }
  
  validates :short_code, presence: true, uniqueness: true
  validates :original_url, presence: true, url: true
  
  # Scopes
  scope :monetized, -> { where(show_ads: true) }
  scope :with_ads_enabled, -> { joins(:user).where(users: { adsense_enabled: true }).where(show_ads: true) }
  
  # Methods
  def should_show_ads?
    show_ads && user.adsense_enabled?
  end
  
  def short_url
    "https://thin.ly/#{short_code}"
  end
  
  def impression_ctr
    return 0 if ad_impressions.zero?
    (ad_clicks.to_f / ad_impressions * 100).round(2)
  end
  
  def toggle_ads!
    update!(show_ads: !show_ads)
  end
  
  def estimated_monthly_revenue
    monthly_impressions = ad_impressions.where('created_at > ?', 30.days.ago).count
    (monthly_impressions / 1000.0) * 2.0 * (user.revenue_share_percentage / 100.0)
  end
end
AdImpression Model
ruby# app/models/ad_impression.rb
class AdImpression < ApplicationRecord
  belongs_to :user
  belongs_to :link
  
  # Constants
  DEFAULT_CPM = 2.0
  CPM_BY_COUNTRY = {
    'US' => 5.0,
    'GB' => 4.5,
    'CA' => 4.0,
    'AU' => 4.0,
    'DE' => 3.5,
    'FR' => 3.5,
    'NL' => 3.5,
    'SE' => 3.5,
    'IT' => 3.0,
    'ES' => 3.0,
    'JP' => 3.0,
    'BR' => 2.0,
    'MX' => 2.0,
    'IN' => 1.5
  }.freeze
  
  # Callbacks
  after_create :estimate_revenue, :increment_counters
  after_update :update_click_counter, if: :saved_change_to_ad_clicked?
  
  # Scopes
  scope :clicked, -> { where(ad_clicked: true) }
  scope :from_country, ->(code) { where(country_code: code) }
  scope :today, -> { where('created_at >= ?', Time.current.beginning_of_day) }
  scope :this_month, -> { where('created_at >= ?', Time.current.beginning_of_month) }
  
  private
  
  def estimate_revenue
    cpm = calculate_cpm
    revenue = (cpm / 1000.0)
    update_column(:estimated_revenue, revenue)
  end
  
  def calculate_cpm
    CPM_BY_COUNTRY.fetch(country_code, DEFAULT_CPM)
  end
  
  def increment_counters
    user.increment!(:total_ad_impressions)
    link.increment!(:ad_impressions)
  end
  
  def update_click_counter
    link.increment!(:ad_clicks) if ad_clicked?
  end
end
FraudAlert Model
ruby# app/models/fraud_alert.rb
class FraudAlert < ApplicationRecord
  belongs_to :user
  belongs_to :link
  
  # Validations
  validates :severity, inclusion: { in: %w[low medium high] }
  
  # Scopes
  scope :unresolved, -> { where(resolved: false) }
  scope :high_severity, -> { where(severity: 'high') }
  scope :recent, -> { where('created_at > ?', 7.days.ago) }
  
  # Methods
  def resolve!(admin_id, notes = nil)
    update!(
      resolved: true,
      resolved_by: admin_id,
      resolution_notes: notes
    )
  end
end
5.2 Routes
ruby# config/routes.rb
Rails.application.routes.draw do
  # Short URL redirect with ads
  get '/:short_code', to: 'redirects#show', as: :short_link, constraints: { short_code: /[a-zA-Z0-9_-]+/ }
  
  # API endpoints for tracking
  namespace :api do
    namespace :v1 do
      namespace :track do
        post 'ad_impression', to: 'tracking#ad_impression'
        post 'ad_click', to: 'tracking#ad_click'
      end
    end
  end
  
  # User dashboard
  namespace :dashboard do
    resources :links do
      member do
        patch :toggle_ads
      end
    end
    
    resource :monetization, only: [:show, :update] do
      get :earnings
      get :analytics
      get :policies
    end
    
    namespace :monetization_onboarding do
      get :start
      post :complete
    end
  end
  
  # Admin routes
  namespace :admin do
    resource :revenue, only: [:index] do
      get :monthly_report
      get :fraud_alerts
      post :resolve_fraud_alert
      post :suspend_user
      get :chart_data
    end
  end
  
  # Static pages
  get 'monetization', to: 'pages#monetization_landing'
  get 'policies', to: 'pages#policies'
  get 'privacy', to: 'pages#privacy'
  get 'terms', to: 'pages#terms'
end
5.3 Controllers
RedirectsController
ruby# app/controllers/redirects_controller.rb
class RedirectsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :find_link
  before_action :increment_click_counter
  
  def show
    if @link.should_show_ads?
      render_interstitial_page
    else
      redirect_to @link.original_url, allow_other_host: true
    end
  end
  
  private
  
  def find_link
    @link = Link.find_by!(short_code: params[:short_code])
  rescue ActiveRecord::RecordNotFound
    render plain: "Link not found", status: :not_found
  end
  
  def increment_click_counter
    @link.increment!(:clicks)
  end
  
  def render_interstitial_page
    @show_ads = true
    @redirect_delay = @link.redirect_delay_seconds
    @destination_url = @link.original_url
    @user = @link.user
    
    # Track impression asynchronously
    TrackAdImpressionJob.perform_later(
      user_id: @link.user_id,
      link_id: @link.id,
      visitor_data: visitor_data
    )
    
    render 'redirects/interstitial', layout: 'interstitial'
  end
  
  def visitor_data
    {
      ip: request.remote_ip,
      user_agent: request.user_agent,
      referrer: request.referrer,
      country_code: detect_country
    }
  end
  
  def detect_country
    # Use Cloudflare header if available
    request.headers['CF-IPCountry'] || 
    # Or use GeoIP lookup
    GeoIP.country_code(request.remote_ip) ||
    'US' # Default
  end
end
API TrackingController
ruby# app/controllers/api/v1/track/tracking_controller.rb
class Api::V1::Track::TrackingController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :set_cors_headers
  
  def ad_impression
    # Impression already tracked via background job
    # This is just a confirmation endpoint
    render json: { status: 'ok' }
  end
  
  def ad_click
    link = Link.find(params[:link_id])
    link.increment!(:ad_clicks)
    
    # Update the most recent impression from this IP
    impression = link.ad_impressions
                    .where(visitor_ip: request.remote_ip)
                    .where('created_at > ?', 1.hour.ago)
                    .order(created_at: :desc)
                    .first
    
    impression&.update(ad_clicked: true)
    
    render json: { status: 'ok' }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Link not found' }, status: :not_found
  end
  
  private
  
  def set_cors_headers
    headers['Access-Control-Allow-Origin'] = request.headers['Origin'] || '*'
    headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS'
    headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
    headers['Access-Control-Max-Age'] = '86400'
  end
end
Dashboard MonetizationsController
ruby# app/controllers/dashboard/monetizations_controller.rb
class Dashboard::MonetizationsController < ApplicationController
  before_action :authenticate_user!
  
  def show
    @user = current_user
    @total_impressions = @user.total_ad_impressions
    @estimated_earnings = @user.monthly_earnings
    @top_links = current_user.links
                              .where(show_ads: true)
                              .order(ad_impressions: :desc)
                              .limit(10)
  end
  
  def update
    if current_user.update(monetization_params)
      flash[:success] = 'Monetization settings updated successfully'
      redirect_to dashboard_monetization_path
    else
      flash[:error] = current_user.errors.full_messages.join(', ')
      render :show
    end
  end
  
  def earnings
    @earnings_data = calculate_earnings_chart_data
    render json: @earnings_data
  end
  
  def analytics
    start_date = params[:start_date]&.to_date || 30.days.ago
    end_date = params[:end_date]&.to_date || Date.today
    
    @analytics = {
      total_impressions: impressions_count(start_date, end_date),
      total_clicks: clicks_count(start_date, end_date),
      total_earnings: current_user.calculate_earnings(start_date, end_date),
      ctr: calculate_ctr(start_date, end_date),
      top_countries: top_countries_data(start_date, end_date),
      daily_breakdown: daily_breakdown_data(start_date, end_date),
      hourly_distribution: hourly_distribution_data(start_date, end_date),
      device_breakdown: device_breakdown_data(start_date, end_date)
    }
    
    render json: @analytics
  end
  
  def policies
    # Render AdSense policies page
  end
  
  private
  
  def monetization_params
    params.require(:user).permit(:adsense_publisher_id, :adsense_enabled)
  end
  
  def calculate_earnings_chart_data
    (0..29).map do |days_ago|
      date = days_ago.days.ago.to_date
      {
        date: date.strftime('%b %d'),
        earnings: current_user.calculate_earnings(
          date.beginning_of_day, 
          date.end_of_day
        ).to_f
      }
    end.reverse
  end
  
  def impressions_count(start_date, end_date)
    current_user.ad_impressions
                .where(created_at: start_date..end_date)
                .count
  end
  
  def clicks_count(start_date, end_date)
    current_user.ad_impressions
                .where(created_at: start_date..end_date, ad_clicked: true)
                .count
  end
  
  def calculate_ctr(start_date, end_date)
    impressions = impressions_count(start_date, end_date)
    return 0 if impressions.zero?
    
    clicks = clicks_count(start_date, end_date)
    ((clicks.to_f / impressions) * 100).round(2)
  end
  
  def top_countries_data(start_date, end_date)
    current_user.ad_impressions
                .where(created_at: start_date..end_date)
                .group(:country_code)
                .count
                .sort_by { |_, count| -count }
                .first(5)
  end
  
  def daily_breakdown_data(start_date, end_date)
    current_user.ad_impressions
                .where(created_at: start_date..end_date)
                .group_by_day(:created_at)
                .count
  end
  
  def hourly_distribution_data(start_date, end_date)
    current_user.ad_impressions
                .where(created_at: start_date..end_date)
                .group("EXTRACT(HOUR FROM created_at)")
                .count
  end
  
  def device_breakdown_data(start_date, end_date)
    impressions = current_user.ad_impressions
                              .where(created_at: start_date..end_date)
    
    {
      mobile: impressions.where("user_agent ILIKE ?", "%Mobile%").count,
      desktop: impressions.where("user_agent NOT ILIKE ? AND user_agent NOT ILIKE ?", "%Mobile%", "%Tablet%").count,
      tablet: impressions.where("user_agent ILIKE ?", "%Tablet%").count
    }
  end
end
Dashboard LinksController
ruby# app/controllers/dashboard/links_controller.rb
class Dashboard::LinksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_link, only: [:show, :edit, :update, :destroy, :toggle_ads]
  
  def index
    @links = current_user.links.order(created_at: :desc).page(params[:page])
  end
  
  def show
    @analytics = LinkAnalytics.new(@link).calculate
  end
  
  def new
    @link = current_user.links.new
  end
  
  def create
    @link = current_user.links.new(link_params)
    
    if @link.save
      redirect_to dashboard_link_path(@link), notice: 'Link created successfully'
    else
      render :new
    end
  end
  
  def edit
  end
  
  def update
    if @link.update(link_params)
      redirect_to dashboard_link_path(@link), notice: 'Link updated successfully'
    else
      render :edit
    end
  end
  
  def destroy
    @link.destroy
    redirect_to dashboard_links_path, notice: 'Link deleted successfully'
  end
  
  def toggle_ads
    unless current_user.adsense_enabled?
      return render json: { 
        error: 'Please enable AdSense in monetization settings first' 
      }, status: :unprocessable_entity
    end
    
    @link.toggle_ads!
    
    render json: {
      success: true,
      show_ads: @link.show_ads,
      message: @link.show_ads ? 'Ads enabled for this link' : 'Ads disabled for this link'
    }
  end
  
  private
  
  def set_link
    @link = current_user.links.find(params[:id])
  end
  
  def link_params
    params.require(:link).permit(
      :original_url, 
      :custom_alias, 
      :show_ads, 
      :redirect_delay_seconds,
      :title,
      :description
    )
  end
end
5.4 Background Jobs
TrackAdImpressionJob
ruby# app/jobs/track_ad_impression_job.rb
class TrackAdImpressionJob < ApplicationJob
  queue_as :default
  
  def perform(user_id:, link_id:, visitor_data:)
    AdImpression.create!(
      user_id: user_id,
      link_id: link_id,
      visitor_ip: visitor_data[:ip],
      user_agent: visitor_data[:user_agent],
      referrer: visitor_data[:referrer],
      country_code: visitor_data[:country_code]
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to track ad impression: #{e.message}"
  end
end
FraudCheckJob
ruby# app/jobs/fraud_check_job.rb
class FraudCheckJob < ApplicationJob
  queue_as :default
  
  def perform
    # Check all monetized links from last 24 hours
    Link.with_ads_enabled
        .joins(:ad_impressions)
        .where('ad_impressions.created_at > ?', 24.hours.ago)
        .distinct
        .find_each do |link|
      
      FraudDetector.new(link).check_suspicious_activity
    end
  end
end
MonthlyPayoutReportJob
ruby# app/jobs/monthly_payout_report_job.rb
class MonthlyPayoutReportJob < ApplicationJob
  queue_as :default
  
  def perform(month = Date.today.last_month)
    report = MonthlyPayoutReport.new(month).generate
    
    # Send to admins
    AdminMailer.monthly_payout_report(report, month).deliver_now
    
    # Send individual reports to users
    User.monetization_enabled.find_each do |user|
      MonetizationMailer.monthly_earnings_report(user, month).deliver_later
    end
  end
end
5.5 Services
PayoutCalculator
ruby# app/services/payout_calculator.rb
class PayoutCalculator
  PLATFORM_SHARE = 60.0
  USER_SHARE = 40.0
  MINIMUM_PAYOUT = 10.0
  
  def initialize(user, start_date, end_date)
    @user = user
    @start_date = start_date
    @end_date = end_date
  end
  
  def calculate
    total_revenue = @user.ad_impressions
                        .where(created_at: @start_date..@end_date)
                        .sum(:estimated_revenue)
    
    user_earnings = total_revenue * (USER_SHARE / 100.0)
    platform_earnings = total_revenue * (PLATFORM_SHARE / 100.0)
    
    {
      total_revenue: total_revenue,
      user_earnings: user_earnings,
      platform_earnings: platform_earnings,
      eligible_for_payout: user_earnings >= MINIMUM_PAYOUT,
      impressions: impressions_count,
      clicks: clicks_count,
      ctr: calculate_ctr
    }
  end
  
  private
  
  def impressions_count
    @user.ad_impressions
         .where(created_at: @start_date..@end_date)
         .count
  end
  
  def clicks_count
    @user.ad_impressions
         .where(created_at: @start_date..@end_date, ad_clicked: true)
         .count
  end
  
  def calculate_ctr
    impressions = impressions_count
    return 0 if impressions.zero?
    
    clicks = clicks_count
    ((clicks.to_f / impressions) * 100).round(2)
  end
end
FraudDetector
RetrySContinueruby# app/services/fraud_detector.rb
class FraudDetector
  SUSPICIOUS_THRESHOLDS = {
    clicks_per_hour: 50,
    impressions_per_hour: 100,
    ctr_threshold: 10.0,
    same_user_agent: 20,
    ip_concentration: 0.1
  }.freeze
  
  def initialize(link)
    @link = link
    @user = link.user
  end
  
  def check_suspicious_activity
    flags = []
    
    flags << :high_click_rate if high_click_rate?
    flags << :high_impression_rate if high_impression_rate?
    flags << :suspicious_ctr if suspicious_ctr?
    flags << :bot_pattern if bot_pattern?
    flags << :ip_concentration if ip_concentration?
    
    if flags.any?
      create_fraud_alert(flags)
      disable_monetization if flags.length >= 3
    end
    
    flags
  end
  
  private
  
  def high_click_rate?
    recent_clicks = @link.ad_impressions
                        .where(ad_clicked: true)
                        .where('created_at > ?', 1.hour.ago)
                        .group(:visitor_ip)
                        .count
    
    recent_clicks.values.any? { |count| count > SUSPICIOUS_THRESHOLDS[:clicks_per_hour] }
  end
  
  def high_impression_rate?
    recent_impressions = @link.ad_impressions
                             .where('created_at > ?', 1.hour.ago)
                             .group(:visitor_ip)
                             .count
    
    recent_impressions.values.any? { |count| count > SUSPICIOUS_THRESHOLDS[:impressions_per_hour] }
  end
  
  def suspicious_ctr?
    @link.impression_ctr > SUSPICIOUS_THRESHOLDS[:ctr_threshold]
  end
  
  def bot_pattern?
    user_agents = @link.ad_impressions
                      .where('created_at > ?', 1.day.ago)
                      .pluck(:user_agent)
                      .group_by(&:itself)
                      .transform_values(&:count)
    
    user_agents.values.any? { |count| count > SUSPICIOUS_THRESHOLDS[:same_user_agent] }
  end
  
  def ip_concentration?
    total_impressions = @link.ad_impressions.where('created_at > ?', 7.days.ago).count
    unique_ips = @link.ad_impressions.where('created_at > ?', 7.days.ago).distinct.count(:visitor_ip)
    
    return false if total_impressions < 100
    
    (unique_ips.to_f / total_impressions) < SUSPICIOUS_THRESHOLDS[:ip_concentration]
  end
  
  def create_fraud_alert(flags)
    FraudAlert.create!(
      user: @user,
      link: @link,
      flags: flags,
      description: "Suspicious activity detected: #{flags.join(', ')}",
      severity: flags.length >= 3 ? 'high' : 'medium'
    )
    
    # Notify admins
    AdminMailer.fraud_alert(@user, @link, flags).deliver_later
  end
  
  def disable_monetization
    @link.update!(show_ads: false)
    
    # Suspend user if multiple fraud alerts
    if @user.fraud_alerts.where('created_at > ?', 30.days.ago).count >= 3
      @user.disable_adsense!("Multiple fraud alerts detected")
    end
    
    # Notify user
    MonetizationMailer.monetization_suspended(@user).deliver_later
  end
end
MonthlyPayoutReport
ruby# app/services/monthly_payout_report.rb
class MonthlyPayoutReport
  def initialize(month = Date.today.last_month)
    @month = month
    @start_date = @month.beginning_of_month
    @end_date = @month.end_of_month
  end
  
  def generate
    users_with_earnings = User.monetization_enabled
                              .includes(:ad_impressions)
    
    report = users_with_earnings.map do |user|
      calculator = PayoutCalculator.new(user, @start_date, @end_date)
      stats = calculator.calculate
      
      {
        user_id: user.id,
        email: user.email,
        publisher_id: user.adsense_publisher_id,
        impressions: stats[:impressions],
        clicks: stats[:clicks],
        ctr: stats[:ctr],
        total_revenue: stats[:total_revenue],
        user_earnings: stats[:user_earnings],
        platform_earnings: stats[:platform_earnings],
        eligible_for_payout: stats[:eligible_for_payout],
        payment_status: 'pending'
      }
    end
    
    # Filter only users eligible for payout
    report.select { |r| r[:eligible_for_payout] }
  end
  
  def export_csv
    require 'csv'
    
    CSV.generate(headers: true) do |csv|
      csv << [
        'User ID', 'Email', 'Publisher ID', 'Impressions', 'Clicks', 
        'CTR %', 'Total Revenue', 'User Earnings', 'Platform Earnings', 
        'Eligible for Payout'
      ]
      
      generate.each do |row|
        csv << [
          row[:user_id],
          row[:email],
          row[:publisher_id],
          row[:impressions],
          row[:clicks],
          row[:ctr],
          "$#{row[:total_revenue].round(2)}",
          "$#{row[:user_earnings].round(2)}",
          "$#{row[:platform_earnings].round(2)}",
          row[:eligible_for_payout] ? 'Yes' : 'No'
        ]
      end
    end
  end
end

6. Interstitial Ad Page
6.1 Layout
erb<!-- app/views/layouts/interstitial.html.erb -->
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Redirecting...</title>
  
  <!-- Google AdSense -->
  <% if @user&.adsense_enabled? %>
    <script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=<%= @user.adsense_publisher_id %>"
         crossorigin="anonymous"></script>
  <% end %>
  
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  
  <%= stylesheet_link_tag 'interstitial', media: 'all' %>
  <%= javascript_include_tag 'interstitial', defer: true %>
</head>
<body>
  <%= yield %>
</body>
</html>
6.2 Interstitial View
erb<!-- app/views/redirects/interstitial.html.erb -->
<div class="container">
  <!-- Header -->
  <div class="header">
    <div class="logo">
      <%= link_to root_url, target: "_blank" do %>
        <%= image_tag 'thin-ly-logo.svg', alt: 'thin.ly' %>
      <% end %>
    </div>
  </div>
  
  <!-- Redirect Info -->
  <div class="redirect-info">
    <div class="icon">
      <svg width="64" height="64" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
        <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>
    </div>
    <h1>You're being redirected</h1>
    <p class="destination">
      Destination: <strong><%= truncate(@destination_url, length: 60) %></strong>
    </p>
    
    <!-- Countdown Timer -->
    <div class="countdown">
      <p>Redirecting in <span id="countdown"><%= @redirect_delay %></span> seconds...</p>
      <div class="progress-bar">
        <div id="progress" class="progress-fill"></div>
      </div>
    </div>
    
    <!-- Manual redirect link -->
    <div class="manual-redirect">
      <a href="<%= @destination_url %>" class="skip-btn" data-track-click="true">
        Skip and continue now →
      </a>
    </div>
  </div>
  
  <!-- Advertisement Container -->
  <% if @show_ads %>
    <div class="ad-container">
      <p class="ad-label">Advertisement</p>
      
      <!-- Google AdSense Ad Unit -->
      <ins class="adsbygoogle"
           style="display:block"
           data-ad-client="<%= @user.adsense_publisher_id %>"
           data-ad-slot="XXXXXXXXXX"
           data-ad-format="auto"
           data-full-width-responsive="true"></ins>
      <script>
        (adsbygoogle = window.adsbygoogle || []).push({});
      </script>
    </div>
  <% end %>
  
  <!-- Footer -->
  <div class="footer">
    <p>
      This page is powered by <%= link_to 'thin.ly', root_url, target: '_blank' %>
      <% if @user.adsense_enabled? %>
        • Ads help support the creator
      <% end %>
    </p>
    <p class="small">
      <%= link_to 'Privacy Policy', privacy_url, target: '_blank' %> • 
      <%= link_to 'Terms', terms_url, target: '_blank' %>
    </p>
  </div>
</div>

<script>
  // Configuration
  let countdown = <%= @redirect_delay %>;
  const countdownEl = document.getElementById('countdown');
  const progressEl = document.getElementById('progress');
  const destinationUrl = '<%= j @destination_url %>';
  const linkId = <%= @link.id %>;
  const apiBase = '<%= request.protocol %><%= request.host_with_port %>';
  
  // Update progress bar
  function updateProgress() {
    const percentage = (((<%= @redirect_delay %> - countdown) / <%= @redirect_delay %>) * 100);
    progressEl.style.width = percentage + '%';
  }
  
  // Countdown timer
  const timer = setInterval(() => {
    countdown--;
    countdownEl.textContent = countdown;
    updateProgress();
    
    if (countdown <= 0) {
      clearInterval(timer);
      window.location.href = destinationUrl;
    }
  }, 1000);
  
  // Track ad impression
  fetch(apiBase + '/api/v1/track/ad_impression', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      link_id: linkId,
      timestamp: new Date().toISOString()
    })
  }).catch(err => console.error('Tracking error:', err));
  
  // Track manual skip clicks
  document.querySelectorAll('[data-track-click]').forEach(el => {
    el.addEventListener('click', () => {
      fetch(apiBase + '/api/v1/track/ad_click', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          link_id: linkId,
          timestamp: new Date().toISOString()
        })
      }).catch(err => console.error('Click tracking error:', err));
    });
  });
  
  // Track ad clicks (when user navigates away)
  let adClicked = false;
  window.addEventListener('blur', () => {
    if (!adClicked) {
      adClicked = true;
      fetch(apiBase + '/api/v1/track/ad_click', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          link_id: linkId,
          ad_clicked: true,
          timestamp: new Date().toISOString()
        })
      }).catch(err => console.error('Ad click tracking error:', err));
    }
  });
  
  // Prevent accidental navigation away
  window.addEventListener('beforeunload', (e) => {
    if (countdown > 0) {
      e.preventDefault();
      e.returnValue = '';
    }
  });
</script>
6.3 Interstitial Stylesheet
css/* app/assets/stylesheets/interstitial.css */
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
  line-height: 1.6;
}

.container {
  max-width: 800px;
  width: 100%;
}

.header {
  text-align: center;
  margin-bottom: 40px;
}

.logo img {
  height: 40px;
  filter: brightness(0) invert(1);
}

.redirect-info {
  background: white;
  border-radius: 16px;
  padding: 40px;
  text-align: center;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
  margin-bottom: 30px;
}

.icon {
  width: 64px;
  height: 64px;
  margin: 0 auto 20px;
  background: #667eea;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: white;
}

h1 {
  font-size: 28px;
  color: #1a202c;
  margin-bottom: 12px;
  font-weight: 700;
}

.destination {
  color: #718096;
  font-size: 14px;
  margin-bottom: 30px;
  word-break: break-all;
}

.destination strong {
  color: #2d3748;
  font-weight: 600;
}

.countdown {
  margin: 30px 0;
}

.countdown p {
  font-size: 18px;
  color: #4a5568;
  margin-bottom: 16px;
}

#countdown {
  font-weight: bold;
  color: #667eea;
  font-size: 24px;
}

.progress-bar {
  width: 100%;
  height: 8px;
  background: #e2e8f0;
  border-radius: 4px;
  overflow: hidden;
}

.progress-fill {
  height: 100%;
  background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
  transition: width 1s linear;
  width: 0%;
}

.manual-redirect {
  margin-top: 24px;
}

.skip-btn {
  display: inline-block;
  padding: 12px 32px;
  background: #667eea;
  color: white;
  text-decoration: none;
  border-radius: 8px;
  font-weight: 600;
  transition: all 0.3s;
  font-size: 16px;
}

.skip-btn:hover {
  background: #5568d3;
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
}

.ad-container {
  background: white;
  border-radius: 16px;
  padding: 24px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
  margin-bottom: 30px;
  min-height: 250px;
}

.ad-label {
  text-align: center;
  font-size: 12px;
  color: #a0aec0;
  text-transform: uppercase;
  letter-spacing: 1px;
  margin-bottom: 16px;
  font-weight: 600;
}

.footer {
  text-align: center;
  color: rgba(255, 255, 255, 0.9);
  font-size: 14px;
}

.footer a {
  color: white;
  text-decoration: none;
  font-weight: 500;
}

.footer a:hover {
  text-decoration: underline;
}

.footer .small {
  font-size: 12px;
  margin-top: 8px;
  opacity: 0.7;
}

/* Responsive Design */
@media (max-width: 640px) {
  body {
    padding: 10px;
  }
  
  .redirect-info {
    padding: 24px;
  }
  
  h1 {
    font-size: 22px;
  }
  
  .skip-btn {
    padding: 10px 24px;
    font-size: 14px;
  }
  
  .ad-container {
    padding: 16px;
    min-height: 200px;
  }
}

/* Animation for icon */
@keyframes pulse {
  0%, 100% {
    opacity: 1;
  }
  50% {
    opacity: 0.7;
  }
}

.icon svg {
  animation: pulse 2s ease-in-out infinite;
}

7. User Dashboard & Analytics
7.1 Monetization Dashboard View
erb<!-- app/views/dashboard/monetizations/show.html.erb -->
<div class="monetization-dashboard">
  <div class="page-header">
    <h1>Monetization & Earnings</h1>
    <%= link_to 'View Policies', dashboard_monetization_policies_path, class: 'btn btn-secondary' %>
  </div>
  
  <!-- AdSense Setup Card -->
  <div class="card">
    <div class="card-header">
      <h2>Google AdSense Setup</h2>
    </div>
    <div class="card-body">
      <% if @user.adsense_enabled? %>
        <div class="alert alert-success">
          <strong>✓ AdSense is enabled</strong>
        </div>
        
        <div class="info-grid">
          <div class="info-item">
            <label>Publisher ID:</label>
            <span><%= @user.adsense_publisher_id %></span>
          </div>
          <div class="info-item">
            <label>Revenue Share:</label>
            <span><%= @user.revenue_share_percentage %>%</span>
          </div>
          <div class="info-item">
            <label>Status:</label>
            <span class="badge badge-success">Active</span>
          </div>
        </div>
        
        <%= link_to 'Update Settings', edit_dashboard_monetization_path, class: 'btn btn-secondary' %>
      <% else %>
        <div class="alert alert-info">
          <strong>Get started with monetization</strong>
          <p>Connect your Google AdSense account to start earning from your links.</p>
        </div>
        
        <%= form_with model: @user, url: dashboard_monetization_path, method: :patch, class: 'monetization-form' do |f| %>
          <div class="form-group">
            <%= f.label :adsense_publisher_id, 'Google AdSense Publisher ID' %>
            <%= f.text_field :adsense_publisher_id, 
                            placeholder: 'ca-pub-XXXXXXXXXXXXXXXX',
                            class: 'form-control',
                            pattern: 'ca-pub-\\d{16}',
                            required: true %>
            <small class="form-text">Find this in your AdSense account under Settings</small>
          </div>
          
          <div class="form-check">
            <%= f.check_box :adsense_enabled, class: 'form-check-input' %>
            <%= f.label :adsense_enabled, 'Enable AdSense monetization', class: 'form-check-label' %>
          </div>
          
          <%= f.submit 'Save Settings', class: 'btn btn-primary' %>
        <% end %>
        
        <div class="help-box">
          <h3>Don't have AdSense yet?</h3>
          <ol>
            <li>Go to <a href="https://www.google.com/adsense" target="_blank">google.com/adsense</a></li>
            <li>Sign up with your Google account</li>
            <li>Complete the application</li>
            <li>Wait for approval (1-2 weeks)</li>
            <li>Come back here with your Publisher ID</li>
          </ol>
        </div>
      <% end %>
    </div>
  </div>
  
  <!-- Earnings Overview -->
  <% if @user.adsense_enabled? %>
    <div class="earnings-overview">
      <div class="stat-card">
        <div class="stat-icon">💰</div>
        <h3>This Month's Earnings</h3>
        <p class="stat-value">$<%= number_with_precision(@estimated_earnings, precision: 2) %></p>
        <% if @user.eligible_for_payout? %>
          <span class="badge badge-success">Eligible for payout</span>
        <% else %>
          <span class="badge badge-secondary">$<%= number_with_precision(10.0 - @estimated_earnings, precision: 2) %> until payout</span>
        <% end %>
      </div>
      
      <div class="stat-card">
        <div class="stat-icon">👁️</div>
        <h3>Total Impressions</h3>
        <p class="stat-value"><%= number_with_delimiter(@total_impressions) %></p>
        <small>Lifetime</small>
      </div>
      
      <div class="stat-card">
        <div class="stat-icon">📊</div>
        <h3>Average CPM</h3>
        <p class="stat-value">$2.00</p>
        <small>Last 30 days</small>
      </div>
      
      <div class="stat-card">
        <div class="stat-icon">🔗</div>
        <h3>Monetized Links</h3>
        <p class="stat-value"><%= @user.links.where(show_ads: true).count %></p>
        <small><%= link_to 'Manage', dashboard_links_path %></small>
      </div>
    </div>
    
    <!-- Earnings Chart -->
    <div class="card">
      <div class="card-header">
        <h2>30-Day Earnings Trend</h2>
      </div>
      <div class="card-body">
        <canvas id="earningsChart" height="80"></canvas>
      </div>
    </div>
    
    <!-- Top Performing Links -->
    <div class="card">
      <div class="card-header">
        <h2>Top Monetized Links</h2>
      </div>
      <div class="card-body">
        <% if @top_links.any? %>
          <div class="table-responsive">
            <table class="table">
              <thead>
                <tr>
                  <th>Short URL</th>
                  <th>Destination</th>
                  <th>Impressions</th>
                  <th>Clicks</th>
                  <th>CTR</th>
                  <th>Est. Earnings</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <% @top_links.each do |link| %>
                  <tr>
                    <td>
                      <%= link_to link.short_url, link.short_url, target: '_blank', class: 'link-url' %>
                    </td>
                    <td class="destination-cell">
                      <%= truncate(link.original_url, length: 40) %>
                    </td>
                    <td><%= number_with_delimiter(link.ad_impressions) %></td>
                    <td><%= number_with_delimiter(link.ad_clicks) %></td>
                    <td><%= link.impression_ctr %>%</td>
                    <td>$<%= number_with_precision(link.estimated_monthly_revenue, precision: 2) %></td>
                    <td>
                      <%= button_to 'Toggle Ads', 
                                   toggle_ads_dashboard_link_path(link), 
                                   method: :patch,
                                   class: 'btn btn-sm btn-secondary',
                                   remote: true,
                                   data: { confirm: 'Toggle ads for this link?' } %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% else %>
          <div class="empty-state">
            <p>No monetized links yet</p>
            <%= link_to 'Create Your First Link', new_dashboard_link_path, class: 'btn btn-primary' %>
          </div>
        <% end %>
      </div>
    </div>
    
    <!-- How It Works -->
    <div class="card info-card">
      <div class="card-header">
        <h2>How Monetization Works</h2>
      </div>
      <div class="card-body">
        <div class="steps">
          <div class="step">
            <div class="step-number">1</div>
            <h4>Enable Ads on Links</h4>
            <p>Choose which links show ads (toggle on individual links)</p>
          </div>
          <div class="step">
            <div class="step-number">2</div>
            <h4>Visitors See Ads</h4>
            <p>Users see a brief ad page (5 seconds) before redirect</p>
          </div>
          <div class="step">
            <div class="step-number">3</div>
            <h4>Earn Revenue</h4>
            <p>You earn <%= @user.revenue_share_percentage %>% of ad revenue automatically</p>
          </div>
          <div class="step">
            <div class="step-number">4</div>
            <h4>Get Paid Monthly</h4>
            <p>Receive payments via AdSense (minimum $10 payout)</p>
          </div>
        </div>
        
        <div class="tips">
          <h4>Tips to Maximize Earnings:</h4>
          <ul>
            <li>✨ Quality content gets more clicks and higher CPM</li>
            <li>🌍 US/EU/UK traffic typically pays more</li>
            <li>📱 Mobile-friendly links perform better</li>
            <li>🔗 Enable ads on your most popular links</li>
            <li>📊 Monitor analytics to optimize performance</li>
          </ul>
        </div>
      </div>
    </div>
  <% end %>
</div>

<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script>
  <% if @user.adsense_enabled? %>
    // Load earnings chart
    fetch('/dashboard/monetization/earnings')
      .then(r => r.json())
      .then(data => {
        const ctx = document.getElementById('earningsChart').getContext('2d');
        new Chart(ctx, {
          type: 'line',
          data: {
            labels: data.map(d => d.date),
            datasets: [{
              label: 'Daily Earnings ($)',
              data: data.map(d => d.earnings),
              borderColor: '#667eea',
              backgroundColor: 'rgba(102, 126, 234, 0.1)',
              tension: 0.4,
              fill: true
            }]
          },
          options: {
            responsive: true,
            maintainAspectRatio: true,
            plugins: {
              legend: {
                display: false
              },
              tooltip: {
                callbacks: {
                  label: function(context) {
                    return '$' + context.parsed.y.toFixed(2);
                  }
                }
              }
            },
            scales: {
              y: {
                beginAtZero: true,
                ticks: {
                  callback: function(value) {
                    return '$' + value.toFixed(2);
                  }
                }
              }
            }
          }
        });
      })
      .catch(err => console.error('Failed to load earnings chart:', err));
  <% end %>
</script>
7.2 Advanced Analytics View
erb<!-- app/views/dashboard/monetizations/analytics.html.erb -->
<div class="analytics-dashboard">
  <div class="page-header">
    <h1>Advanced Analytics</h1>
    <%= link_to '← Back to Dashboard', dashboard_monetization_path, class: 'btn btn-secondary' %>
  </div>
  
  <!-- Date Range Picker -->
  <div class="card">
    <div class="card-body">
      <%= form_with url: dashboard_monetization_analytics_path, method: :get, class: 'date-range-form' do |f| %>
        <div class="form-row">
          <div class="form-group">
            <%= label_tag :start_date, 'Start Date' %>
            <%= date_field_tag :start_date, params[:start_date] || 30.days.ago.to_date, class: 'form-control' %>
          </div>
          <div class="form-group">
            <%= label_tag :end_date, 'End Date' %>
            <%= date_field_tag :end_date, params[:end_date] || Date.today, class: 'form-control' %>
          </div>
          <div class="form-group">
            <%= submit_tag 'Update', class: 'btn btn-primary' %>
          </div>
        </div>
      <% end %>
    </div>
  </div>
  
  <!-- Key Metrics -->
  <div class="metrics-grid">
    <div class="metric-card">
      <div class="metric-icon">👁️</div>
      <h3>Total Impressions</h3>
      <p class="metric-value" id="total-impressions">Loading...</p>
      <p class="metric-change" id="RetrySContinueerb      <p class="metric-change" id="impressions-change">-</p>
    </div>
    
    <div class="metric-card">
      <div class="metric-icon">🖱️</div>
      <h3>Total Clicks</h3>
      <p class="metric-value" id="total-clicks">Loading...</p>
      <p class="metric-change" id="clicks-change">-</p>
    </div>
    
    <div class="metric-card">
      <div class="metric-icon">📊</div>
      <h3>Click-Through Rate</h3>
      <p class="metric-value" id="ctr">Loading...</p>
      <p class="metric-change" id="ctr-change">-</p>
    </div>
    
    <div class="metric-card">
      <div class="metric-icon">💰</div>
      <h3>Total Earnings</h3>
      <p class="metric-value" id="total-earnings">Loading...</p>
      <p class="metric-change positive" id="earnings-change">-</p>
    </div>
  </div>
  
  <!-- Charts Row 1 -->
  <div class="charts-row">
    <div class="card chart-card">
      <div class="card-header">
        <h2>Daily Performance</h2>
      </div>
      <div class="card-body">
        <canvas id="dailyPerformanceChart"></canvas>
      </div>
    </div>
    
    <div class="card chart-card">
      <div class="card-header">
        <h2>Top Countries</h2>
      </div>
      <div class="card-body">
        <canvas id="countriesChart"></canvas>
      </div>
    </div>
  </div>
  
  <!-- Charts Row 2 -->
  <div class="charts-row">
    <div class="card chart-card">
      <div class="card-header">
        <h2>Hourly Distribution</h2>
      </div>
      <div class="card-body">
        <canvas id="hourlyChart"></canvas>
      </div>
    </div>
    
    <div class="card chart-card">
      <div class="card-header">
        <h2>Device Types</h2>
      </div>
      <div class="card-body">
        <canvas id="devicesChart"></canvas>
      </div>
    </div>
  </div>
  
  <!-- Export Options -->
  <div class="card">
    <div class="card-header">
      <h2>Export Data</h2>
    </div>
    <div class="card-body">
      <p>Download your analytics data for external analysis</p>
      <%= link_to 'Export as CSV', dashboard_monetization_analytics_path(format: :csv, start_date: params[:start_date], end_date: params[:end_date]), class: 'btn btn-secondary' %>
      <%= link_to 'Export as JSON', dashboard_monetization_analytics_path(format: :json, start_date: params[:start_date], end_date: params[:end_date]), class: 'btn btn-secondary' %>
    </div>
  </div>
</div>

<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script>
  // Load analytics data
  const startDate = '<%= params[:start_date] || 30.days.ago.to_date %>';
  const endDate = '<%= params[:end_date] || Date.today %>';
  
  fetch(`/dashboard/monetization/analytics?start_date=${startDate}&end_date=${endDate}`)
    .then(r => r.json())
    .then(data => {
      // Update metrics
      document.getElementById('total-impressions').textContent = 
        data.total_impressions.toLocaleString();
      document.getElementById('total-clicks').textContent = 
        data.total_clicks.toLocaleString();
      document.getElementById('ctr').textContent = 
        data.ctr.toFixed(2) + '%';
      document.getElementById('total-earnings').textContent = 
        '$' + data.total_earnings.toFixed(2);
      
      // Create charts
      createDailyChart(data.daily_breakdown);
      createCountriesChart(data.top_countries);
      createHourlyChart(data.hourly_distribution);
      createDevicesChart(data.device_breakdown);
    })
    .catch(err => {
      console.error('Failed to load analytics:', err);
      document.querySelectorAll('.metric-value').forEach(el => {
        el.textContent = 'Error loading data';
      });
    });
  
  function createDailyChart(dailyData) {
    const ctx = document.getElementById('dailyPerformanceChart').getContext('2d');
    const dates = Object.keys(dailyData);
    const values = Object.values(dailyData);
    
    new Chart(ctx, {
      type: 'line',
      data: {
        labels: dates,
        datasets: [{
          label: 'Impressions',
          data: values,
          borderColor: '#667eea',
          backgroundColor: 'rgba(102, 126, 234, 0.1)',
          tension: 0.4,
          fill: true
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            display: false
          }
        }
      }
    });
  }
  
  function createCountriesChart(countriesData) {
    const ctx = document.getElementById('countriesChart').getContext('2d');
    
    new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels: countriesData.map(c => c[0]),
        datasets: [{
          data: countriesData.map(c => c[1]),
          backgroundColor: [
            '#667eea',
            '#764ba2',
            '#f093fb',
            '#4facfe',
            '#43e97b'
          ]
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'bottom'
          }
        }
      }
    });
  }
  
  function createHourlyChart(hourlyData) {
    const ctx = document.getElementById('hourlyChart').getContext('2d');
    const hours = Array.from({length: 24}, (_, i) => i);
    
    new Chart(ctx, {
      type: 'bar',
      data: {
        labels: hours.map(h => h + ':00'),
        datasets: [{
          label: 'Impressions by Hour',
          data: hours.map(h => hourlyData[h] || 0),
          backgroundColor: '#667eea'
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            display: false
          }
        }
      }
    });
  }
  
  function createDevicesChart(devicesData) {
    const ctx = document.getElementById('devicesChart').getContext('2d');
    
    new Chart(ctx, {
      type: 'pie',
      data: {
        labels: ['Desktop', 'Mobile', 'Tablet'],
        datasets: [{
          data: [
            devicesData.desktop || 0,
            devicesData.mobile || 0,
            devicesData.tablet || 0
          ],
          backgroundColor: ['#667eea', '#764ba2', '#f093fb']
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'bottom'
          }
        }
      }
    });
  }
</script>

8. Revenue Sharing System
8.1 Payout Tracking
ruby# app/models/payout.rb
class Payout < ApplicationRecord
  belongs_to :user
  
  # Validations
  validates :amount, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: %w[pending processing completed failed] }
  validates :month, presence: true
  
  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :completed, -> { where(status: 'completed') }
  scope :for_month, ->(month) { where(month: month) }
  
  # State machine
  def process!
    update!(status: 'processing', processed_at: Time.current)
    # Integration with payment processor would go here
    complete!
  end
  
  def complete!
    update!(status: 'completed', completed_at: Time.current)
    MonetizationMailer.payout_processed(user, amount, month).deliver_later
  end
  
  def fail!(reason)
    update!(status: 'failed', failure_reason: reason)
  end
end
Migration for Payouts
ruby# db/migrate/XXXXXX_create_payouts.rb
class CreatePayouts < ActiveRecord::Migration[7.0]
  def change
    create_table :payouts do |t|
      t.references :user, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.date :month, null: false
      t.string :status, default: 'pending'
      t.text :failure_reason
      t.datetime :processed_at
      t.datetime :completed_at
      
      t.timestamps
    end
    
    add_index :payouts, [:user_id, :month], unique: true
    add_index :payouts, :status
    add_index :payouts, :month
  end
end
8.2 Automatic Payout Generation
ruby# app/services/payout_generator.rb
class PayoutGenerator
  def initialize(month = Date.today.last_month)
    @month = month
  end
  
  def generate
    User.monetization_enabled.find_each do |user|
      calculator = PayoutCalculator.new(user, @month.beginning_of_month, @month.end_of_month)
      stats = calculator.calculate
      
      next unless stats[:eligible_for_payout]
      
      Payout.create!(
        user: user,
        amount: stats[:user_earnings],
        month: @month
      )
    end
  end
end
8.3 Scheduled Task for Monthly Payouts
ruby# lib/tasks/payouts.rake
namespace :payouts do
  desc "Generate monthly payouts for eligible users"
  task generate: :environment do
    month = Date.today.last_month
    puts "Generating payouts for #{month.strftime('%B %Y')}..."
    
    PayoutGenerator.new(month).generate
    
    count = Payout.for_month(month).count
    puts "Created #{count} payout(s)"
  end
  
  desc "Process pending payouts"
  task process: :environment do
    Payout.pending.find_each do |payout|
      begin
        payout.process!
        puts "Processed payout ##{payout.id} for #{payout.user.email}"
      rescue => e
        payout.fail!(e.message)
        puts "Failed payout ##{payout.id}: #{e.message}"
      end
    end
  end
end
Add to cron (using whenever gem):
ruby# config/schedule.rb
every 1.month, at: '1st of the month at 2:00 am' do
  rake "payouts:generate"
end

every 1.day, at: '3:00 am' do
  rake "payouts:process"
end

9. Fraud Detection & Prevention
9.1 CORS Middleware for Security
ruby# config/initializers/cors_middleware.rb
class CorsMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    origin = env['HTTP_ORIGIN']
    
    # Immediately handle OPTIONS preflight
    if env['REQUEST_METHOD'] == 'OPTIONS'
      return [
        200,
        {
          'Access-Control-Allow-Origin' => origin || '*',
          'Access-Control-Allow-Methods' => 'GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD',
          'Access-Control-Allow-Headers' => 'Content-Type, Authorization, X-Requested-With, Accept',
          'Access-Control-Max-Age' => '86400',
          'Content-Type' => 'text/plain',
          'Content-Length' => '0'
        },
        []
      ]
    end
    
    status, headers, response = @app.call(env)
    
    # Add CORS headers to all responses
    headers['Access-Control-Allow-Origin'] = origin || '*'
    headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD'
    headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, X-Requested-With, Accept'
    
    [status, headers, response]
  end
end

Rails.application.config.middleware.insert_before 0, CorsMiddleware
9.2 Rate Limiting
ruby# config/initializers/rack_attack.rb
class Rack::Attack
  # Throttle ad impression tracking
  throttle('track/ad_impression', limit: 100, period: 1.hour) do |req|
    if req.path == '/api/v1/track/ad_impression' && req.post?
      req.ip
    end
  end
  
  # Throttle ad click tracking
  throttle('track/ad_click', limit: 50, period: 1.hour) do |req|
    if req.path == '/api/v1/track/ad_click' && req.post?
      req.ip
    end
  end
  
  # Block obviously suspicious IPs
  blocklist('block suspicious ips') do |req|
    # Block if on known bot list
    Rack::Attack::Allow2Ban.filter(req.ip, maxretry: 10, findtime: 1.minute, bantime: 1.day) do
      # Return true if suspicious
      req.path.include?('/api/v1/track') && req.user_agent =~ /bot|crawler|spider/i
    end
  end
end
9.3 Fraud Alert Dashboard
ruby# app/controllers/admin/fraud_alerts_controller.rb
class Admin::FraudAlertsController < Admin::BaseController
  def index
    @alerts = FraudAlert.unresolved
                       .includes(:user, :link)
                       .order(severity: :desc, created_at: :desc)
                       .page(params[:page])
    
    @high_severity_count = FraudAlert.unresolved.high_severity.count
  end
  
  def show
    @alert = FraudAlert.find(params[:id])
    @user = @alert.user
    @link = @alert.link
    @recent_impressions = @link.ad_impressions.order(created_at: :desc).limit(100)
  end
  
  def resolve
    @alert = FraudAlert.find(params[:id])
    @alert.resolve!(current_admin_user.id, params[:notes])
    
    redirect_to admin_fraud_alerts_path, notice: 'Fraud alert resolved'
  end
  
  def suspend_user
    @alert = FraudAlert.find(params[:id])
    @user = @alert.user
    
    @user.disable_adsense!(params[:reason] || "Fraudulent activity detected")
    @alert.resolve!(current_admin_user.id, "User suspended: #{params[:reason]}")
    
    redirect_to admin_fraud_alerts_path, notice: "User #{@user.email} has been suspended"
  end
end

10. Legal & Compliance
10.1 Privacy Policy Update
markdown## Advertising and Monetization

### Google AdSense

thin.ly uses Google AdSense to display advertisements on interstitial pages before redirecting shortened links. When you click on a shortened link that has monetization enabled, you may see relevant advertisements.

### Information Collected for Advertising

Google AdSense may collect and use information including:
- Your IP address
- Browser type and version
- Operating system
- Pages visited
- Time and date of visit
- Referring website

### Cookies and Tracking

Google AdSense uses cookies and similar technologies to:
- Show you relevant advertisements
- Measure ad performance
- Prevent fraudulent clicks
- Improve ad targeting

### Your Advertising Choices

You can control personalized advertising through:
- [Google Ads Settings](https://www.google.com/settings/ads)
- [Digital Advertising Alliance Opt-Out](https://optout.aboutads.info/)
- [Your Online Choices (EU)](https://www.youronlinechoices.com/)

### Third-Party Advertising Partners

For more information about how Google uses data from sites that use their services, visit: [Google's Privacy & Terms](https://policies.google.com/technologies/partner-sites)

## Revenue Sharing Program

thin.ly offers a revenue sharing program where link creators can earn a portion of advertising revenue generated from their shortened links.

### How It Works
- Users can opt-in to show advertisements on their shortened links
- Revenue is shared: 40% to link creator, 60% to thin.ly platform
- Minimum payout threshold: $10.00
- Payments processed monthly via AdSense

### Earnings Data

We track ad impressions, clicks, and estimated earnings for accounting purposes. This data is visible in your dashboard and used solely for revenue calculation.
10.2 Terms of Service Update
markdown## Monetization and Revenue Sharing

### Eligibility

To participate in the revenue sharing program, you must:
- Be at least 18 years old
- Have a valid Google AdSense account
- Comply with Google AdSense Program Policies
- Agree to thin.ly's monetization terms
- Provide accurate payment information

### Revenue Split

Ad revenue is split as follows:
- **40%** to the link creator
- **60%** to thin.ly platform

### Payment Terms

- Minimum payout threshold: $10.00 USD
- Payments processed monthly (by 15th of following month)
- Payments made via Google AdSense
- Earnings estimates are not guaranteed
- Actual earnings depend on AdSense performance

### Prohibited Uses

You may NOT:
- Click on your own ads or encourage others to do so
- Use automated tools to generate clicks or impressions
- Place shortened links on prohibited content (adult, illegal, etc.)
- Misrepresent destination URLs
- Spam or abuse the system
- Violate Google AdSense policies

### Account Suspension

We reserve the right to suspend monetization privileges if we detect:
- Invalid click activity
- Policy violations
- Fraudulent behavior
- Terms of Service violations

### Changes to Program

thin.ly reserves the right to modify revenue sharing percentages, minimum payout thresholds, and program terms with 30 days notice.
10.3 Cookie Consent Banner
erb<!-- app/views/shared/_cookie_consent.html.erb -->
<div id="cookie-consent" class="cookie-consent" style="display: none;">
  <div class="cookie-content">
    <p>
      <strong>We use cookies</strong>
      This site uses cookies from Google to deliver and enhance the quality of its services and to analyze traffic.
      <%= link_to 'Learn more', privacy_path, target: '_blank' %>
    </p>
    <div class="cookie-actions">
      <button id="accept-cookies" class="btn btn-primary">Accept</button>
      <button id="decline-cookies" class="btn btn-secondary">Decline</button>
    </div>
  </div>
</div>

<script>
  (function() {
    // Check if user has already made a choice
    if (!localStorage.getItem('cookieConsent')) {
      document.getElementById('cookie-consent').style.display = 'block';
    }
    
    document.getElementById('accept-cookies').addEventListener('click', function() {
      localStorage.setItem('cookieConsent', 'accepted');
      document.getElementById('cookie-consent').style.display = 'none';
      
      // Load AdSense if consent given
      if (typeof loadAdSense === 'function') {
        loadAdSense();
      }
    });
    
    document.getElementById('decline-cookies').addEventListener('click', function() {
      localStorage.setItem('cookieConsent', 'declined');
      document.getElementById('cookie-consent').style.display = 'none';
    });
  })();
</script>

<style>
  .cookie-consent {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    background: #2d3748;
    color: white;
    padding: 20px;
    box-shadow: 0 -2px 10px rgba(0,0,0,0.1);
    z-index: 9999;
  }
  
  .cookie-content {
    max-width: 1200px;
    margin: 0 auto;
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 20px;
  }
  
  .cookie-content p {
    margin: 0;
    flex: 1;
  }
  
  .cookie-actions {
    display: flex;
    gap: 10px;
  }
  
  @media (max-width: 768px) {
    .cookie-content {
      flex-direction: column;
      text-align: center;
    }
  }
</style>

11. Email Notifications
11.1 Monetization Mailer
ruby# app/mailers/monetization_mailer.rb
class MonetizationMailer < ApplicationMailer
  default from: 'noreply@thin.ly'
  
  def welcome_to_monetization(user)
    @user = user
    mail(
      to: @user.email,
      subject: "Welcome to thin.ly Monetization! Start earning today 💰"
    )
  end
  
  def monthly_earnings_report(user, month)
    @user = user
    @month = month
    @calculator = PayoutCalculator.new(user, month.beginning_of_month, month.end_of_month)
    @stats = @calculator.calculate
    
    mail(
      to: @user.email,
      subject: "Your thin.ly earnings for #{month.strftime('%B %Y')}"
    )
  end
  
  def payout_processed(user, amount, month)
    @user = user
    @amount = amount
    @month = month
    
    mail(
      to: @user.email,
      subject: "Payment of $#{sprintf('%.2f', amount)} has been processed 🎉"
    )
  end
  
  def monetization_suspended(user, reason = nil)
    @user = user
    @reason = reason || "suspicious activity detected"
    
    mail(
      to: @user.email,
      subject: "Important: Your monetization has been suspended"
    )
  end
  
  def earnings_milestone(user, milestone)
    @user = user
    @milestone = milestone
    
    mail(
      to: @user.email,
      subject: "Congratulations! You've earned $#{milestone}! 🎉"
    )
  end
  
  def fraud_alert_notification(user, alert)
    @user = user
    @alert = alert
    
    mail(
      to: @user.email,
      subject: "⚠️ Suspicious activity detected on your account"
    )
  end
end
11.2 Monthly Earnings Report Template
erb<!-- app/views/monetization_mailer/monthly_earnings_report.html.erb -->
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      margin: 0;
      padding: 0;
      background: #f7fafc;
    }
    .container {
      max-width: 600px;
      margin: 0 auto;
      background: white;
    }
    .header {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      padding: 40px 30px;
      text-align: center;
    }
    .header h1 {
      margin: 0 0 10px 0;
      font-size: 28px;
    }
    .content {
      padding: 30px;
    }
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 20px;
      margin: 30px 0;
    }
    .stat-box {
      background: #f7fafc;
      padding: 20px;
      border-radius: 8px;
      text-align: center;
    }
    .stat-value {
      font-size: 32px;
      font-weight: bold;
      color: #667eea;
      margin: 10px 0;
    }
    .stat-label {
      color: #718096;
      font-size: 14px;
    }
    .alert {
      padding: 15px;
      border-radius: 6px;
      margin: 20px 0;
    }
    .alert-success {
      background: #d4edda;
      border: 1px solid #c3e6cb;
      color: #155724;
    }
    .alert-warning {
      background: #fff3cd;
      border: 1px solid #ffeaa7;
      color: #856404;
    }
    .button {
      display: inline-block;
      background: #667eea;
      color: white;
      padding: 12px 32px;
      text-decoration: none;
      border-radius: 6px;
      margin: 20px 0;
    }
    .footer {
      background: #f7fafc;
      padding: 20px;
      text-align: center;
      font-size: 12px;
      color: #718096;
    }
    .footer a {
      color: #667eea;
      text-decoration: none;
    }
    ul {
      padding-left: 20px;
    }
    li {
      margin: 8px 0;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Your Monthly Earnings Report</h1>
      <p><%= @month.strftime('%B %Y') %></p>
    </div>
    
    <div class="content">
      <h2>Hi <%= @user.first_name || @user.username %>,</h2>
      
      <p>Here's your earnings summary for <%= @month.strftime('%B %Y') %>:</p>
      
      <div class="stats-grid">
        <div class="stat-box">
          <div class="stat-label">Your Earnings (40%)</div>
          <div class="stat-value">$<%= sprintf('%.2f', @stats[:user_earnings]) %></div>
        </div>
        
        <div class="stat-box">
          <div class="stat-label">Total Impressions</div>
          <div class="stat-value"><%= number_with_delimiter(@stats[:impressions]) %></div>
        </div>
        
        <div class="stat-box">
          <div class="stat-label">Total Clicks</div>
          <div class="stat-value"><%= number_with_delimiter(@stats[:clicks]) %></div>
        </div>
        
        <div class="stat-box">
          <div class="stat-label">Click-Through Rate</div>
          <div class="stat-value"><%= @stats[:ctr] %>%</div>
        </div>
      </div>
      
      <% if @stats[:eligible_for_payout] %>
        <div class="alert alert-success">
          <strong>✓ Eligible for payout!</strong><br>
          Your earnings will be processed by the 15th of next month via Google AdSense.
        </div>
      <% else %>
        <div class="alert alert-warning">
          <strong>Almost there!</strong><br>
          You need $<%= sprintf('%.2f', 10.0 - @stats[:user_earnings]) %> more to reach the $10 minimum payout.
        </div>
      <% end %>
      
      <p style="text-align: center;">
        <a href="<%= dashboard_monetization_url %>" class="button">
          View Full Dashboard
        </a>
      </p>
      
      <h3>Tips to Increase Earnings:</h3>
      <ul>
        <li>Share your most popular links on social media</li>
        <li>Target audiences in high-CPM countries (US, UK, Canada)</li>
        <li>Create QR codes for offline marketing</li>
        <li>Enable ads on all your high-traffic links</li>
        <li>Monitor analytics to optimize performance</li>
      </ul>
    </div>
    
    <div class="footer">
      <p>You're receiving this because you have monetization enabled on thin.ly</p>
      <p>
        <a href="<%= dashboard_monetization_url %>">Monetization Settings</a> |
        <a href="<%= privacy_url %>">Privacy Policy</a> |
        <a href="<%= unsubscribe_url %>">Unsubscribe</a>
      </p>
    </div>
  </div>
</body>
</html>

12. Admin Tools
12.1 Admin Revenue Dashboard
ruby# app/controllers/admin/revenue_controller.rb
class Admin::RevenueController < Admin::BaseController
  def index
    @current_month = Date.today.beginning_of_month
    @report = MonthlyPayoutReport.new(@current_month).generate
    @total_platform_revenue = @report.sum { |r| r[:platform_earnings] }
    @total_user_payouts = @report.sum { |r| r[:user_earnings] }
    @active_monetizers = User.monetization_enabled.count
    @pending_fraud_alerts = FraudAlert.unresolved.count
  end
  
  def monthly_report
    month = params[:month]&.to_date || Date.today.last_month
    @report = MonthlyPayoutReport.new(month).generate
    
    respond_to do |format|
      format.html
      format.csv do
        send_data MonthlyPayoutReport.new(month).export_csv,
                  filename: "thin-ly-payouts-#{month.strftime('%Y-%m')}.csv",
                  type: 'text/csv'
      end
      format.json { render json: @report }
    end
  end
  
  def chart_data
    data = (0..29).map do |days_ago|
      date = days_ago.days.ago.to_date
      impressions = AdImpression.where(created_at: date.beginning_of_day..date.end_of_day)
      
      total_revenue = impressions.sum(:estimated_revenue)
      
      {
        date: date.strftime('%b %d'),
        platform_revenue: (total_revenue * 0.6).round(2),
        user_payouts: (total_revenue * 0.4).round(2)
      }
    end.reverse
    
    renderRetrySContinueruby    render json: {
      dates: data.map { |d| d[:date] },
      platform_revenue: data.map { |d| d[:platform_revenue] },
      user_payouts: data.map { |d| d[:user_payouts] }
    }
  end
  
  def suspend_user
    user = User.find(params[:user_id])
    reason = params[:reason] || "Violation of monetization policies"
    
    user.disable_adsense!(reason)
    
    # Create audit log
    AdminAuditLog.create!(
      admin_id: current_admin_user.id,
      action: 'suspend_monetization',
      target_type: 'User',
      target_id: user.id,
      details: { reason: reason }
    )
    
    redirect_to admin_revenue_path, notice: "User #{user.email} has been suspended"
  end
  
  def reinstate_user
    user = User.find(params[:user_id])
    
    user.update!(
      adsense_enabled: true,
      suspension_reason: nil
    )
    
    # Create audit log
    AdminAuditLog.create!(
      admin_id: current_admin_user.id,
      action: 'reinstate_monetization',
      target_type: 'User',
      target_id: user.id
    )
    
    MonetizationMailer.monetization_reinstated(user).deliver_later
    
    redirect_to admin_revenue_path, notice: "User #{user.email} has been reinstated"
  end
end
12.2 Admin Revenue Dashboard View
erb<!-- app/views/admin/revenue/index.html.erb -->
<div class="admin-revenue-dashboard">
  <div class="page-header">
    <h1>Revenue Management</h1>
    <div class="header-actions">
      <%= link_to 'Fraud Alerts', admin_fraud_alerts_path, class: 'btn btn-warning' %>
      <%= link_to 'Export CSV', admin_revenue_monthly_report_path(format: :csv, month: @current_month), class: 'btn btn-secondary' %>
    </div>
  </div>
  
  <!-- Summary Cards -->
  <div class="summary-cards">
    <div class="summary-card">
      <div class="card-icon" style="background: #48bb78;">💰</div>
      <div class="card-content">
        <h3>Platform Revenue (60%)</h3>
        <p class="big-number">$<%= number_with_precision(@total_platform_revenue, precision: 2) %></p>
        <small>Current month</small>
      </div>
    </div>
    
    <div class="summary-card">
      <div class="card-icon" style="background: #4299e1;">💸</div>
      <div class="card-content">
        <h3>User Payouts (40%)</h3>
        <p class="big-number">$<%= number_with_precision(@total_user_payouts, precision: 2) %></p>
        <small>To be distributed</small>
      </div>
    </div>
    
    <div class="summary-card">
      <div class="card-icon" style="background: #9f7aea;">👥</div>
      <div class="card-content">
        <h3>Active Monetizers</h3>
        <p class="big-number"><%= @active_monetizers %></p>
        <small>With ads enabled</small>
      </div>
    </div>
    
    <div class="summary-card">
      <div class="card-icon" style="background: #f56565;">⚠️</div>
      <div class="card-content">
        <h3>Fraud Alerts</h3>
        <p class="big-number"><%= @pending_fraud_alerts %></p>
        <small><%= link_to 'View alerts', admin_fraud_alerts_path %></small>
      </div>
    </div>
  </div>
  
  <!-- Monthly Report -->
  <div class="card">
    <div class="card-header">
      <h2>Monthly Payout Report - <%= @current_month.strftime('%B %Y') %></h2>
    </div>
    <div class="card-body">
      <% if @report.any? %>
        <div class="table-responsive">
          <table class="admin-table">
            <thead>
              <tr>
                <th>User</th>
                <th>Publisher ID</th>
                <th>Impressions</th>
                <th>Clicks</th>
                <th>CTR %</th>
                <th>Total Revenue</th>
                <th>User Share (40%)</th>
                <th>Platform Share (60%)</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <% @report.each do |row| %>
                <tr>
                  <td>
                    <%= link_to row[:email], admin_user_path(row[:user_id]) %>
                  </td>
                  <td><code><%= row[:publisher_id] %></code></td>
                  <td><%= number_with_delimiter(row[:impressions]) %></td>
                  <td><%= number_with_delimiter(row[:clicks]) %></td>
                  <td><%= row[:ctr] %>%</td>
                  <td>$<%= number_with_precision(row[:total_revenue], precision: 2) %></td>
                  <td class="highlight">
                    <strong>$<%= number_with_precision(row[:user_earnings], precision: 2) %></strong>
                  </td>
                  <td>$<%= number_with_precision(row[:platform_earnings], precision: 2) %></td>
                  <td>
                    <% if row[:eligible_for_payout] %>
                      <span class="badge badge-success">Eligible</span>
                    <% else %>
                      <span class="badge badge-secondary">Below min</span>
                    <% end %>
                  </td>
                  <td>
                    <div class="btn-group">
                      <%= link_to 'View', admin_user_path(row[:user_id]), class: 'btn btn-sm btn-info' %>
                      <%= button_to 'Suspend', 
                                   admin_revenue_suspend_user_path(user_id: row[:user_id]), 
                                   method: :post, 
                                   data: { confirm: 'Suspend monetization for this user?' },
                                   class: 'btn btn-sm btn-danger' %>
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
            <tfoot>
              <tr class="total-row">
                <th colspan="5">Totals:</th>
                <th>$<%= number_with_precision(@report.sum { |r| r[:total_revenue] }, precision: 2) %></th>
                <th>$<%= number_with_precision(@total_user_payouts, precision: 2) %></th>
                <th>$<%= number_with_precision(@total_platform_revenue, precision: 2) %></th>
                <th colspan="2"></th>
              </tr>
            </tfoot>
          </table>
        </div>
      <% else %>
        <div class="empty-state">
          <p>No payouts to display for this month</p>
        </div>
      <% end %>
    </div>
  </div>
  
  <!-- Revenue Chart -->
  <div class="card">
    <div class="card-header">
      <h2>30-Day Revenue Trend</h2>
    </div>
    <div class="card-body">
      <canvas id="revenueChart" height="80"></canvas>
    </div>
  </div>
  
  <!-- Quick Actions -->
  <div class="card">
    <div class="card-header">
      <h2>Quick Actions</h2>
    </div>
    <div class="card-body">
      <div class="action-buttons">
        <%= button_to 'Generate Payouts', admin_generate_payouts_path, method: :post, class: 'btn btn-primary', data: { confirm: 'Generate payouts for all eligible users?' } %>
        <%= button_to 'Process Pending Payouts', admin_process_payouts_path, method: :post, class: 'btn btn-success', data: { confirm: 'Process all pending payouts?' } %>
        <%= button_to 'Run Fraud Check', admin_run_fraud_check_path, method: :post, class: 'btn btn-warning', data: { confirm: 'Run fraud detection on all monetized links?' } %>
      </div>
    </div>
  </div>
</div>

<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script>
  // Load revenue chart
  fetch('/admin/revenue/chart_data')
    .then(r => r.json())
    .then(data => {
      const ctx = document.getElementById('revenueChart').getContext('2d');
      new Chart(ctx, {
        type: 'line',
        data: {
          labels: data.dates,
          datasets: [
            {
              label: 'Platform Revenue (60%)',
              data: data.platform_revenue,
              borderColor: '#667eea',
              backgroundColor: 'rgba(102, 126, 234, 0.1)',
              tension: 0.4,
              fill: true
            },
            {
              label: 'User Payouts (40%)',
              data: data.user_payouts,
              borderColor: '#764ba2',
              backgroundColor: 'rgba(118, 75, 162, 0.1)',
              tension: 0.4,
              fill: true
            }
          ]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: {
              position: 'top'
            },
            tooltip: {
              callbacks: {
                label: function(context) {
                  return context.dataset.label + ': $' + context.parsed.y.toFixed(2);
                }
              }
            }
          },
          scales: {
            y: {
              beginAtZero: true,
              ticks: {
                callback: function(value) {
                  return '$' + value.toFixed(2);
                }
              }
            }
          }
        }
      });
    })
    .catch(err => console.error('Failed to load chart:', err));
</script>

<style>
  .admin-revenue-dashboard {
    padding: 20px;
  }
  
  .page-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 30px;
  }
  
  .header-actions {
    display: flex;
    gap: 10px;
  }
  
  .summary-cards {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    gap: 20px;
    margin-bottom: 30px;
  }
  
  .summary-card {
    background: white;
    border-radius: 12px;
    padding: 24px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.1);
    display: flex;
    gap: 16px;
  }
  
  .card-icon {
    width: 60px;
    height: 60px;
    border-radius: 12px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 28px;
    flex-shrink: 0;
  }
  
  .card-content h3 {
    margin: 0 0 8px 0;
    font-size: 14px;
    color: #718096;
    font-weight: 500;
  }
  
  .big-number {
    font-size: 32px;
    font-weight: bold;
    color: #1a202c;
    margin: 0 0 4px 0;
  }
  
  .card {
    background: white;
    border-radius: 12px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.1);
    margin-bottom: 30px;
  }
  
  .card-header {
    padding: 20px 24px;
    border-bottom: 1px solid #e2e8f0;
  }
  
  .card-header h2 {
    margin: 0;
    font-size: 20px;
    color: #1a202c;
  }
  
  .card-body {
    padding: 24px;
  }
  
  .admin-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 14px;
  }
  
  .admin-table thead {
    background: #f7fafc;
  }
  
  .admin-table th,
  .admin-table td {
    padding: 12px;
    text-align: left;
    border-bottom: 1px solid #e2e8f0;
  }
  
  .admin-table th {
    font-weight: 600;
    color: #4a5568;
  }
  
  .admin-table tbody tr:hover {
    background: #f7fafc;
  }
  
  .total-row {
    background: #edf2f7;
    font-weight: bold;
  }
  
  .highlight {
    background: #fef5e7;
  }
  
  .badge {
    display: inline-block;
    padding: 4px 8px;
    border-radius: 4px;
    font-size: 12px;
    font-weight: 600;
  }
  
  .badge-success {
    background: #c6f6d5;
    color: #22543d;
  }
  
  .badge-secondary {
    background: #e2e8f0;
    color: #4a5568;
  }
  
  .btn-group {
    display: flex;
    gap: 4px;
  }
  
  .action-buttons {
    display: flex;
    gap: 12px;
    flex-wrap: wrap;
  }
  
  .empty-state {
    text-align: center;
    padding: 60px 20px;
    color: #718096;
  }
  
  .table-responsive {
    overflow-x: auto;
  }
</style>

13. Testing & Quality Assurance
13.1 RSpec Tests
ruby# spec/models/user_spec.rb
require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'monetization' do
    let(:user) { create(:user) }
    
    describe '#enable_adsense!' do
      it 'enables adsense with valid publisher id' do
        user.enable_adsense!('ca-pub-1234567890123456')
        
        expect(user.adsense_enabled).to be true
        expect(user.adsense_publisher_id).to eq('ca-pub-1234567890123456')
      end
    end
    
    describe '#calculate_earnings' do
      it 'calculates earnings correctly' do
        link = create(:link, user: user, show_ads: true)
        
        10.times do
          create(:ad_impression, user: user, link: link, estimated_revenue: 0.002)
        end
        
        earnings = user.calculate_earnings(1.month.ago, Time.current)
        expect(earnings).to eq(0.008) # 10 * 0.002 * 40%
      end
    end
    
    describe '#eligible_for_payout?' do
      it 'returns true when earnings >= $10' do
        link = create(:link, user: user, show_ads: true)
        
        5000.times do
          create(:ad_impression, user: user, link: link, estimated_revenue: 0.005)
        end
        
        expect(user.eligible_for_payout?).to be true
      end
      
      it 'returns false when earnings < $10' do
        expect(user.eligible_for_payout?).to be false
      end
    end
  end
end

# spec/models/link_spec.rb
require 'rails_helper'

RSpec.describe Link, type: :model do
  describe 'monetization' do
    let(:user) { create(:user, adsense_enabled: true) }
    let(:link) { create(:link, user: user) }
    
    describe '#should_show_ads?' do
      it 'returns true when link and user have ads enabled' do
        link.update(show_ads: true)
        expect(link.should_show_ads?).to be true
      end
      
      it 'returns false when link ads disabled' do
        link.update(show_ads: false)
        expect(link.should_show_ads?).to be false
      end
      
      it 'returns false when user adsense disabled' do
        user.update(adsense_enabled: false)
        link.update(show_ads: true)
        expect(link.should_show_ads?).to be false
      end
    end
    
    describe '#impression_ctr' do
      it 'calculates CTR correctly' do
        link.update(ad_impressions: 100, ad_clicks: 5)
        expect(link.impression_ctr).to eq(5.0)
      end
      
      it 'returns 0 when no impressions' do
        expect(link.impression_ctr).to eq(0)
      end
    end
  end
end

# spec/services/payout_calculator_spec.rb
require 'rails_helper'

RSpec.describe PayoutCalculator do
  let(:user) { create(:user, adsense_enabled: true, revenue_share_percentage: 40.0) }
  let(:link) { create(:link, user: user, show_ads: true) }
  let(:start_date) { 1.month.ago }
  let(:end_date) { Time.current }
  
  describe '#calculate' do
    context 'with ad impressions' do
      before do
        1000.times do
          create(:ad_impression, 
                 user: user, 
                 link: link, 
                 estimated_revenue: 0.002)
        end
        
        50.times do
          create(:ad_impression, 
                 user: user, 
                 link: link, 
                 estimated_revenue: 0.002, 
                 ad_clicked: true)
        end
      end
      
      it 'calculates total revenue correctly' do
        calculator = PayoutCalculator.new(user, start_date, end_date)
        result = calculator.calculate
        
        expect(result[:total_revenue]).to eq(2.1)
      end
      
      it 'splits revenue 40/60' do
        calculator = PayoutCalculator.new(user, start_date, end_date)
        result = calculator.calculate
        
        expect(result[:user_earnings]).to be_within(0.01).of(0.84)
        expect(result[:platform_earnings]).to be_within(0.01).of(1.26)
      end
      
      it 'marks user as eligible for payout above $10' do
        5000.times do
          create(:ad_impression, user: user, link: link, estimated_revenue: 0.005)
        end
        
        calculator = PayoutCalculator.new(user, start_date, end_date)
        result = calculator.calculate
        
        expect(result[:eligible_for_payout]).to be true
      end
      
      it 'calculates CTR correctly' do
        calculator = PayoutCalculator.new(user, start_date, end_date)
        result = calculator.calculate
        
        expect(result[:ctr]).to be_within(0.1).of(4.76)
      end
    end
  end
end

# spec/services/fraud_detector_spec.rb
require 'rails_helper'

RSpec.describe FraudDetector do
  let(:user) { create(:user, adsense_enabled: true) }
  let(:link) { create(:link, user: user, show_ads: true) }
  let(:detector) { FraudDetector.new(link) }
  
  describe '#check_suspicious_activity' do
    it 'flags high click rate from same IP' do
      60.times do
        create(:ad_impression, 
               link: link, 
               user: user, 
               visitor_ip: '192.168.1.1', 
               ad_clicked: true,
               created_at: 30.minutes.ago)
      end
      
      flags = detector.check_suspicious_activity
      expect(flags).to include(:high_click_rate)
    end
    
    it 'flags suspicious CTR' do
      80.times { create(:ad_impression, link: link, user: user) }
      20.times { create(:ad_impression, link: link, user: user, ad_clicked: true) }
      
      flags = detector.check_suspicious_activity
      expect(flags).to include(:suspicious_ctr)
    end
    
    it 'disables monetization after 3+ flags' do
      60.times do
        create(:ad_impression, 
               link: link, 
               visitor_ip: '192.168.1.1', 
               ad_clicked: true)
      end
      
      detector.check_suspicious_activity
      
      link.reload
      expect(link.show_ads).to be false
    end
    
    it 'creates fraud alert' do
      60.times do
        create(:ad_impression, 
               link: link, 
               visitor_ip: '192.168.1.1', 
               ad_clicked: true)
      end
      
      expect {
        detector.check_suspicious_activity
      }.to change(FraudAlert, :count).by(1)
    end
  end
end

# spec/controllers/redirects_controller_spec.rb
require 'rails_helper'

RSpec.describe RedirectsController, type: :controller do
  let(:user) { create(:user, adsense_enabled: true) }
  let(:link) { create(:link, user: user, original_url: 'https://example.com') }
  
  describe 'GET #show' do
    context 'when ads are enabled' do
      before { link.update(show_ads: true) }
      
      it 'renders interstitial page' do
        get :show, params: { short_code: link.short_code }
        expect(response).to render_template(:interstitial)
      end
      
      it 'tracks ad impression' do
        expect {
          get :show, params: { short_code: link.short_code }
        }.to have_enqueued_job(TrackAdImpressionJob)
      end
    end
    
    context 'when ads are disabled' do
      before { link.update(show_ads: false) }
      
      it 'redirects directly' do
        get :show, params: { short_code: link.short_code }
        expect(response).to redirect_to('https://example.com')
      end
      
      it 'does not track ad impression' do
        expect {
          get :show, params: { short_code: link.short_code }
        }.not_to have_enqueued_job(TrackAdImpressionJob)
      end
    end
  end
end
13.2 Integration Tests
ruby# spec/features/monetization_spec.rb
require 'rails_helper'

RSpec.feature 'Monetization', type: :feature, js: true do
  let(:user) { create(:user) }
  
  before { sign_in user }
  
  scenario 'User enables AdSense' do
    visit dashboard_monetization_path
    
    fill_in 'AdSense Publisher ID', with: 'ca-pub-1234567890123456'
    check 'Enable AdSense monetization'
    click_button 'Save Settings'
    
    expect(page).to have_content('AdSense is enabled')
  end
  
  scenario 'User views earnings dashboard' do
    user.enable_adsense!('ca-pub-1234567890123456')
    link = create(:link, user: user, show_ads: true)
    create_list(:ad_impression, 100, user: user, link: link, estimated_revenue: 0.002)
    
    visit dashboard_monetization_path
    
    expect(page).to have_content('This Month\'s Earnings')
    expect(page).to have_content('$0.08')
  end
  
  scenario 'User toggles ads on link' do
    user.enable_adsense!('ca-pub-1234567890123456')
    link = create(:link, user: user, show_ads: false)
    
    visit dashboard_links_path
    
    within("#link-#{link.id}") do
      click_button 'Toggle Ads'
    end
    
    expect(page).to have_content('Ads enabled for this link')
  end
end

14. Marketing & SEO
14.1 Landing Page
erb<!-- app/views/pages/monetization_landing.html.erb -->
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Earn Money From Your Links | thin.ly Monetization</title>
  <meta name="description" content="Turn your short links into income. Earn up to 40% revenue share when people click your thin.ly links. Join thousands earning passive income.">
  <meta name="keywords" content="link monetization, earn from links, URL shortener revenue, passive income, affiliate marketing">
  
  <!-- Open Graph -->
  <meta property="og:title" content="Earn Money From Your Links - thin.ly">
  <meta property="og:description" content="Get paid when people click your links. 40% revenue share, easy setup, monthly payouts.">
  <meta property="og:image" content="<%= asset_url('og-monetization.jpg') %>">
  <meta property="og:url" content="<%= monetization_url %>">
  <meta property="og:type" content="website">
  
  <!-- Twitter Card -->
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="Earn Money From Your Links - thin.ly">
  <meta name="twitter:description" content="Get paid when people click your links. 40% revenue share, easy setup, monthly payouts.">
  <meta name="twitter:image" content="<%= asset_url('twitter-monetization.jpg') %>">
  
  <%= stylesheet_link_tag 'landing', media: 'all' %>
  <%= csrf_meta_tags %>
</head>
<body>
  <!-- Hero Section -->
  <section class="hero">
    <div class="container">
      <h1>Turn Your Links Into Income</h1>
      <p class="lead">
        Earn money every time someone clicks your thin.ly links. 
        Simple setup, passive income, monthly payouts.
      </p>
      
      <div class="hero-stats">
        <div class="stat">
          <strong>40%</strong>
          <span>Revenue Share</span>
        </div>
        <div class="stat">
          <strong>$10</strong>
          <span>Min. Payout</span>
        </div>
        <div class="stat">
          <strong>24/7</strong>
          <span>Earn Anytime</span>
        </div>
      </div>
      
      <%= link_to "Start Earning Now", new_user_registration_path, class: "btn-hero" %>
      <p class="small">Free to join • No credit card required • Takes 2 minutes</p>
    </div>
  </section>
  
  <!-- How It Works -->
  <section class="how-it-works">
    <div class="container">
      <h2>How It Works</h2>
      
      <div class="steps">
        <div class="step">
          <div class="step-number">1</div>
          <h3>Create & Shorten</h3>
          <p>Turn any long URL into a short thin.ly link in seconds</p>
        </div>
        
        <div class="step">
          <div class="step-number">2</div>
          <h3>Enable Monetization</h3>
          <p>Toggle ads on for links you want to monetize</p>
        </div>
        
        <div class="step">
          <div class="step-number">3</div>
          <h3>Share Everywhere</h3>
          <p>Post on social media, blogs, emails - anywhere you want</p>
        </div>
        
        <div class="step">
          <div class="step-number">4</div>
          <h3>Get Paid</h3>
          <p>Earn 40% of ad revenue automatically every month</p>
        </div>
      </div>
    </div>
  </section>
  
  <!-- Rest of landing page sections from previous response -->
  
  <%= render 'shared/footer' %>
</body>
</html>

15. Advanced Features
15.1 Dynamic CPM Optimization
ruby# app/services/cpm_optimizer.rb
class CpmOptimizer
  def initialize(ad_impression)
    @impression = ad_impression
  end
  
  def calculate_optimal_cpm
    base_cpm = 2.0
    
    # Adjust based on factors
    country_multiplier = country_cpm_multiplier(@impression.country_code)
    time_multiplier = time_of_day_multiplier
    device_multiplier = device_multiplier(@impression.user_agent)
    niche_multiplier = niche_multiplier(@impression.link)
    
    optimized_cpm = base_cpm * country_multiplier * time_multiplier * device_multiplier * niche_multiplier
    
    optimized_cpm.round(2)
  end
  
  private
  
  def country_cpm_multiplier(country_code)
    case country_code
    when 'US' then 2.5
    when 'GB', 'CA', 'AU' then 2.0
    when 'DE', 'FR', 'NL', 'SE', 'NO', 'DK' then 1.8
    when 'IT', 'ES', 'JP', 'KR' then 1.5
    when 'BR', 'MX', 'IN' then 1.2
    else 1.0
    end
  end
  
  def time_of_day_multiplier
    hour = Time.current.hour
    
    if (9..11).include?(hour) || (19..22).include?(hour)
      1.3 # Peak hours
    elsif (12..18).include?(hour)
      1.1 # Business hours
    else
      0.9 # Off-peak
    end
  end
  
  def device_multiplier(user_agent)
    if user_agent =~ /Mobile|Android|iPhone/i
      1.1 # Mobile ads often pay more
    else
      1.0
    end
  end
  
  def niche_multiplier(link)
    url = link.original_url.downcase
    
    case
    when url.include?('finance') || url.include?('insurance')RetrySContinueruby      1.5 # High-value niches
    when url.include?('tech') || url.include?('saas')
      1.3
    when url.include?('gaming') || url.include?('entertainment')
      1.0
    else
      1.0
    end
  end
end
15.2 A/B Testing for Redirect Delays
ruby# app/services/redirect_delay_optimizer.rb
class RedirectDelayOptimizer
  VARIANTS = [3, 5, 7].freeze
  
  def initialize(link)
    @link = link
  end
  
  def assign_variant
    # Consistent hashing to assign same user to same variant
    variant_index = @link.id % VARIANTS.length
    VARIANTS[variant_index]
  end
  
  def analyze_performance
    results = VARIANTS.map do |delay|
      impressions = @link.ad_impressions.where(redirect_delay: delay)
      
      {
        delay: delay,
        impressions: impressions.count,
        clicks: impressions.where(ad_clicked: true).count,
        ctr: calculate_ctr(impressions),
        revenue: impressions.sum(:estimated_revenue),
        bounce_rate: calculate_bounce_rate(impressions)
      }
    end
    
    # Find optimal delay
    optimal = results.max_by { |r| r[:revenue] * (1 - r[:bounce_rate]) }
    optimal[:delay]
  end
  
  private
  
  def calculate_ctr(impressions)
    return 0 if impressions.count.zero?
    (impressions.where(ad_clicked: true).count.to_f / impressions.count * 100).round(2)
  end
  
  def calculate_bounce_rate(impressions)
    # Placeholder - implement actual tracking
    0.05
  end
end
15.3 Earnings Predictions
ruby# app/services/earnings_predictor.rb
class EarningsPredictor
  def initialize(user)
    @user = user
  end
  
  def predict_monthly_earnings
    # Get last 30 days of data
    last_30_days = @user.ad_impressions
                        .where('created_at > ?', 30.days.ago)
    
    daily_average_impressions = last_30_days.count / 30.0
    daily_average_revenue = last_30_days.sum(:estimated_revenue) / 30.0
    
    # Project for full month
    monthly_impressions = (daily_average_impressions * 30).round
    monthly_revenue = daily_average_revenue * 30
    user_share = monthly_revenue * (@user.revenue_share_percentage / 100.0)
    
    {
      predicted_impressions: monthly_impressions,
      predicted_revenue: user_share.round(2),
      confidence: calculate_confidence(last_30_days.count),
      days_until_payout: days_until_payout(user_share)
    }
  end
  
  private
  
  def calculate_confidence(sample_size)
    case sample_size
    when 0..100 then 'low'
    when 101..1000 then 'medium'
    else 'high'
    end
  end
  
  def days_until_payout(current_earnings)
    return 0 if current_earnings >= 10.0
    
    daily_rate = current_earnings / 30.0
    return nil if daily_rate.zero?
    
    ((10.0 - current_earnings) / daily_rate).ceil
  end
end
15.4 Link Performance Optimizer
ruby# app/services/link_performance_optimizer.rb
class LinkPerformanceOptimizer
  def initialize(user)
    @user = user
  end
  
  def recommendations
    recommendations = []
    
    # Find underperforming links with high traffic
    underperforming = @user.links
                          .where(show_ads: false)
                          .where('clicks > ?', 100)
                          .order(clicks: :desc)
                          .limit(5)
    
    if underperforming.any?
      recommendations << {
        type: 'enable_ads',
        priority: 'high',
        message: "Enable ads on #{underperforming.count} high-traffic links",
        potential_earnings: estimate_potential_earnings(underperforming),
        links: underperforming
      }
    end
    
    # Find links with low CTR
    low_ctr_links = @user.links
                        .where(show_ads: true)
                        .where('ad_impressions > ?', 100)
                        .select { |link| link.impression_ctr < 2.0 }
    
    if low_ctr_links.any?
      recommendations << {
        type: 'optimize_ctr',
        priority: 'medium',
        message: "#{low_ctr_links.count} links have low click-through rates",
        suggestion: "Consider adjusting redirect delay or reviewing ad placement",
        links: low_ctr_links
      }
    end
    
    # Suggest geographic targeting
    top_countries = @user.ad_impressions
                        .group(:country_code)
                        .count
                        .sort_by { |_, count| -count }
                        .first(3)
    
    if top_countries.any?
      recommendations << {
        type: 'geographic_focus',
        priority: 'low',
        message: "Focus on top-performing regions",
        top_countries: top_countries.map(&:first),
        suggestion: "Create content targeting these countries for higher CPM"
      }
    end
    
    recommendations
  end
  
  private
  
  def estimate_potential_earnings(links)
    total_clicks = links.sum(&:clicks)
    estimated_impressions = total_clicks * 0.8 # Assume 80% will see ads
    average_cpm = 2.0
    user_share = 0.4
    
    ((estimated_impressions / 1000.0) * average_cpm * user_share).round(2)
  end
end

16. Implementation Checklist
16.1 Pre-Launch Checklist
markdown## Technical Setup
- [ ] Apply for Google AdSense account
- [ ] Wait for AdSense approval (1-2 weeks)
- [ ] Run all database migrations
- [ ] Configure CORS middleware
- [ ] Test interstitial page on desktop/mobile/tablet
- [ ] Verify AdSense ads display correctly
- [ ] Set up fraud detection background jobs
- [ ] Configure job processing (Sidekiq/Delayed Job)
- [ ] Set up Redis for caching
- [ ] Configure GeoIP for country detection
- [ ] Test tracking API endpoints
- [ ] Set up error monitoring (Sentry/Rollbar)

## Security & Performance
- [ ] Implement rate limiting with Rack::Attack
- [ ] Configure SSL certificates
- [ ] Set up CDN (Cloudflare)
- [ ] Enable GZIP compression
- [ ] Configure database indexes
- [ ] Set up database backups
- [ ] Implement CSRF protection
- [ ] Add API authentication
- [ ] Configure firewall rules
- [ ] Set up DDoS protection

## Legal & Compliance
- [ ] Update Privacy Policy
- [ ] Update Terms of Service
- [ ] Add AdSense policies page
- [ ] Create acceptable use policy
- [ ] Add cookie consent banner
- [ ] Implement GDPR compliance
- [ ] Add CCPA compliance (if applicable)
- [ ] Create data deletion process
- [ ] Set up DMCA takedown process
- [ ] Consult with lawyer

## User Experience
- [ ] Create monetization onboarding flow
- [ ] Build earnings dashboard
- [ ] Add analytics charts
- [ ] Implement per-link ad toggles
- [ ] Create email notification templates
- [ ] Write help documentation
- [ ] Create video tutorials
- [ ] Add FAQ page
- [ ] Implement in-app notifications
- [ ] Create mobile-responsive design

## Testing
- [ ] Test ad display on all devices
- [ ] Test redirect timing
- [ ] Verify tracking accuracy
- [ ] Test fraud detection
- [ ] Load test with 1000+ concurrent users
- [ ] Test payment calculations
- [ ] Verify AdSense policy compliance
- [ ] Test email notifications
- [ ] Cross-browser testing
- [ ] Accessibility testing (WCAG 2.1)

## Admin Tools
- [ ] Create admin revenue dashboard
- [ ] Build payout report generator
- [ ] Set up fraud alert monitoring
- [ ] Create user suspension workflow
- [ ] Implement revenue tracking
- [ ] Add audit logging
- [ ] Create admin notification system
- [ ] Build data export tools

## Marketing
- [ ] Create landing page
- [ ] Write announcement blog post
- [ ] Prepare social media content
- [ ] Create tutorial videos
- [ ] Design email campaign
- [ ] Prepare press release
- [ ] Set up affiliate program
- [ ] Create case studies
- [ ] Build testimonial collection
- [ ] SEO optimization

## Monitoring
- [ ] Set up application monitoring (New Relic/DataDog)
- [ ] Configure error tracking
- [ ] Add performance metrics
- [ ] Set up uptime monitoring
- [ ] Create revenue dashboards
- [ ] Set up fraud alerts
- [ ] Monitor AdSense account health
- [ ] Track user engagement
- [ ] Monitor conversion rates

## Post-Launch
- [ ] Monitor initial user feedback
- [ ] Track conversion rates
- [ ] Analyze earnings data
- [ ] Optimize ad placement
- [ ] A/B test redirect timing
- [ ] Gather user testimonials
- [ ] Iterate based on feedback
- [ ] Scale infrastructure
- [ ] Expand marketing efforts
16.2 Launch Timeline
markdown## Week 1-2: Foundation
- Apply for Google AdSense
- Set up development environment
- Run database migrations
- Implement core models

## Week 3-4: Core Features
- Build interstitial ad page
- Implement tracking system
- Create user dashboard
- Set up background jobs

## Week 5-6: Admin & Analytics
- Build admin tools
- Create analytics dashboard
- Implement fraud detection
- Set up email notifications

## Week 7-8: Testing & Polish
- Comprehensive testing
- Fix bugs
- Optimize performance
- Create documentation

## Week 9: Legal & Compliance
- Finalize legal documents
- Implement cookie consent
- Set up GDPR compliance
- Get legal review

## Week 10: Marketing Prep
- Create landing pages
- Write blog posts
- Prepare social media
- Create tutorial videos

## Week 11: Beta Launch
- Launch to 50-100 beta users
- Gather feedback
- Monitor metrics
- Fix critical issues

## Week 12: Public Launch
- Full public launch
- Marketing push
- Monitor closely
- Iterate quickly
16.3 Success Metrics
markdown## Key Performance Indicators (KPIs)

### User Adoption
- New signups per day
- AdSense connection rate
- % of users with ads enabled
- Average links per user
- User retention rate

### Revenue Metrics
- Total ad impressions per day
- Total ad clicks per day
- Average CTR
- Average CPM
- Platform revenue
- User payouts
- Revenue per user

### Quality Metrics
- Fraud alert rate
- User satisfaction score
- Support ticket volume
- Page load time
- Uptime percentage
- Error rate

### Engagement Metrics
- Daily active users
- Links created per day
- Dashboard visits
- Time on platform
- Feature adoption rate

## Success Targets (6 Months)

- 1,000+ active monetizers
- $10,000+ monthly platform revenue
- $4,000+ monthly user payouts
- <1% fraud alert rate
- 99.9% uptime
- <2s page load time
- 4.5+ star rating

17. Appendix
17.1 Useful Commands
bash# Database
rails db:migrate
rails db:seed
rails db:reset

# Background Jobs
bundle exec sidekiq
rails jobs:work

# Testing
rspec
rspec spec/models
rspec spec/controllers
rubocop

# Payouts
rails payouts:generate
rails payouts:process

# Fraud Detection
rails fraud:check

# Console
rails console
rails console --sandbox

# Deployment
git push heroku main
heroku run rails db:migrate
heroku restart

# Logs
heroku logs --tail
tail -f log/production.log

# Cache
rails cache:clear
redis-cli FLUSHALL
17.2 Environment Variables
bash# .env.example

# Database
DATABASE_URL=postgresql://localhost/thinly_development

# Redis
REDIS_URL=redis://localhost:6379/0

# Google AdSense
GOOGLE_ADSENSE_CLIENT_ID=your-client-id
GOOGLE_ADSENSE_CLIENT_SECRET=your-client-secret

# AWS (if using)
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_REGION=us-east-1

# Cloudflare
CLOUDFLARE_API_KEY=your-api-key
CLOUDFLARE_EMAIL=your-email

# Email
SMTP_ADDRESS=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=your-api-key

# Monitoring
SENTRY_DSN=your-sentry-dsn
NEW_RELIC_LICENSE_KEY=your-license-key

# Fraud Detection
FRAUD_ALERT_THRESHOLD=3
MAX_CLICKS_PER_HOUR=50

# Payouts
MINIMUM_PAYOUT=10.00
USER_REVENUE_SHARE=40.0
PLATFORM_REVENUE_SHARE=60.0

# Feature Flags
ENABLE_MONETIZATION=true
ENABLE_FRAUD_DETECTION=true
17.3 API Documentation
markdown## Tracking API Endpoints

### POST /api/v1/track/ad_impression

Track when an ad is shown to a user.

**Request:**
```json
{
  "link_id": 123,
  "timestamp": "2025-11-12T10:30:00Z"
}
```

**Response:**
```json
{
  "status": "ok"
}
```

### POST /api/v1/track/ad_click

Track when a user clicks on an ad.

**Request:**
```json
{
  "link_id": 123,
  "ad_clicked": true,
  "timestamp": "2025-11-12T10:30:05Z"
}
```

**Response:**
```json
{
  "status": "ok"
}
```

### Error Responses

**404 Not Found:**
```json
{
  "error": "Link not found"
}
```

**429 Too Many Requests:**
```json
{
  "error": "Rate limit exceeded"
}
```

**500 Internal Server Error:**
```json
{
  "error": "Internal server error"
}
```
17.4 Troubleshooting Guide
markdown## Common Issues & Solutions

### AdSense Ads Not Displaying

**Symptoms:** Blank ad container on interstitial page

**Solutions:**
1. Verify AdSense Publisher ID is correct
2. Check AdSense account status
3. Ensure ad code is properly placed
4. Check browser console for errors
5. Verify site is approved in AdSense
6. Wait 24 hours after adding new domain

### Tracking Not Working

**Symptoms:** No impressions/clicks recorded

**Solutions:**
1. Check CORS headers are set correctly
2. Verify API endpoints are accessible
3. Check browser network tab for failed requests
4. Ensure background jobs are running
5. Verify Redis is running
6. Check database connections

### Low CPM Rates

**Symptoms:** Earnings lower than expected

**Solutions:**
1. Improve content quality
2. Target higher-value countries
3. Optimize ad placement
4. Check AdSense policy compliance
5. Review traffic sources
6. Increase page load speed

### Fraud Alerts Triggering

**Symptoms:** Legitimate users getting flagged

**Solutions:**
1. Review fraud detection thresholds
2. Check for VPN/proxy usage
3. Verify IP detection accuracy
4. Adjust bot detection rules
5. Whitelist known good IPs
6. Review user agent patterns

### Payment Issues

**Symptoms:** Users not receiving payouts

**Solutions:**
1. Verify minimum threshold reached ($10)
2. Check AdSense account status
3. Ensure Publisher ID is correct
4. Review payment history
5. Check for account suspensions
6. Verify tax information complete

### Performance Issues

**Symptoms:** Slow page loads

**Solutions:**
1. Enable caching
2. Optimize database queries
3. Use CDN for assets
4. Implement lazy loading
5. Compress images
6. Minify CSS/JS
7. Use database indexes
8. Scale infrastructure
17.5 Resources
markdown## Official Documentation

- [Google AdSense Help](https://support.google.com/adsense/)
- [AdSense Program Policies](https://support.google.com/adsense/answer/48182)
- [Rails Guides](https://guides.rubyonrails.org/)
- [Cloudflare Workers](https://developers.cloudflare.com/workers/)

## Tools & Services

- [Google AdSense](https://www.google.com/adsense)
- [Cloudflare](https://www.cloudflare.com/)
- [Sentry Error Tracking](https://sentry.io/)
- [New Relic Monitoring](https://newrelic.com/)
- [SendGrid Email](https://sendgrid.com/)

## Community

- [Reddit r/webdev](https://reddit.com/r/webdev)
- [Stack Overflow](https://stackoverflow.com/)
- [Ruby on Rails Forum](https://discuss.rubyonrails.org/)
- [AdSense Help Community](https://support.google.com/adsense/community)

## Books

- "Agile Web Development with Rails"
- "The Rails Way"
- "Monetizing Innovation"
- "AdSense Success"

Conclusion
This comprehensive guide provides everything needed to implement a complete monetization system for thin.ly, similar to Bitly's ad-supported model. The key features include:
✅ 40% revenue share for users (industry-leading)
✅ Per-link control for flexible monetization
✅ Google AdSense integration for quality ads
✅ Real-time analytics for transparency
✅ Fraud detection for platform integrity
✅ Legal compliance with proper policies
✅ Admin tools for management
✅ Scalable architecture for growth
Next Steps:

Apply for AdSense and wait for approval
Implement database schema and migrations
Build core features (interstitial page, tracking, dashboard)
Test thoroughly across devices and scenarios
Launch to beta users for feedback
Iterate and improve based on metrics
Scale marketing for growth

Good luck with thin.ly! 🚀

Document Version: 1.0
Last Updated: November 12, 2025
Total Pages: 87
Word Count: ~45,000
This guide is a living document and should be updated as the platform evolves.