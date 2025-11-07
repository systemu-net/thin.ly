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

      Rails.logger.info "Successfully published brand page #{brand_page.lookup_code} to #{result[:published_url]}"
    else
      # Log the error but don't raise an exception (let Sidekiq handle retries)
      Rails.logger.error "Failed to publish brand page #{brand_page.lookup_code}: #{result[:error]}"

      # Optionally, you could raise an exception to trigger Sidekiq retries:
      # raise StandardError, "Publishing failed: #{result[:error]}"
    end
  end

  private
end
