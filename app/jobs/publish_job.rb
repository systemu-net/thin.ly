require "sidekiq"
require "rest-client"

class PublishJob
  include Sidekiq::Job
  queue_as :default

  def perform(lookup_code)
    brand_page = BrandPage.includes(:user).find_by(lookup_code: lookup_code)

    return unless brand_page

    publisher = GithubPagesPublisher.new(brand_page.user, brand_page)
    result = publisher.publish

    if result[:success]
      # Update the published version with the publishing results
      brand_page.update!(
        published_url: result[:published_url],
        published_at: result[:published_at]
      )

      # Also update the draft version with the published URL and timestamp
      if brand_page.draft_version
        brand_page.draft_version.update!(
          published_url: result[:published_url],
          published_at: result[:published_at]
        )
      end

      Rails.logger.info "Successfully published brand page #{brand_page.lookup_code} to #{result[:published_url]}"
    else
      Rails.logger.error "Failed to publish brand page #{brand_page.lookup_code}: #{result[:error]}"
    end
  end
end
