# Scheduled Sidekiq job that enforces time-based lifecycle policies.
# Runs every minute via sidekiq-scheduler (or cron) on the governance queue.
#
# 1. Auto-activate draft links whose activates_at has passed.
# 2. Auto-expire active links whose expires_at has passed.
# 3. Auto-expire active links that have reached their click_cap.
class LinkLifecycleManagerJob
  include Sidekiq::Job

  sidekiq_options queue: :governance, retry: 3

  def perform
    auto_activate!
    auto_expire_by_time!
    auto_expire_by_cap!
  end

  private

  def auto_activate!
    Link.where(state: "draft")
        .where(governance_enabled: true)
        .where("activates_at IS NOT NULL AND activates_at <= ?", Time.current)
        .find_each do |link|
      link.transition_to!("active", reason: "Auto-activated (scheduled activation time)")
      Rails.logger.info("[Governance] Auto-activated link #{link.lookup_code}")
    end
  end

  def auto_expire_by_time!
    Link.where(state: "active")
        .where(governance_enabled: true)
        .where("expires_at IS NOT NULL AND expires_at <= ?", Time.current)
        .find_each do |link|
      link.transition_to!("expired", reason: "Auto-expired (expiration time reached)")
      Rails.logger.info("[Governance] Auto-expired link #{link.lookup_code} (time)")
    end
  end

  def auto_expire_by_cap!
    Link.where(state: "active")
        .where(governance_enabled: true)
        .where("click_cap IS NOT NULL AND clicks_count >= click_cap")
        .find_each do |link|
      link.transition_to!("expired", reason: "Auto-expired (click cap reached)")
      Rails.logger.info("[Governance] Auto-expired link #{link.lookup_code} (click cap)")
    end
  end
end
