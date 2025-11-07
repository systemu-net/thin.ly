require "sidekiq"
require "rest-client"

class UnpublishJob
  include Sidekiq::Job
  queue_as :default

  def perform(lookup_code)
    brand_page = BrandPage.includes(:user).find_by(lookup_code: lookup_code)

    return unless brand_page

    publisher = GithubPagesPublisher.new(brand_page.user, brand_page)
    result = publisher.unpublish

    if result[:success]
      # Delete this published version after successful unpublishing
      brand_page.destroy!

      Rails.logger.info "Successfully unpublished and deleted brand page #{brand_page.lookup_code}"
    else
      Rails.logger.error "Failed to unpublish brand page #{brand_page.lookup_code}: #{result[:error]}"

      brand_page.update!(status: BrandPage::STATUS_PUBLISHED)
    end
  end
end
