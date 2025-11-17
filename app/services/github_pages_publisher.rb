# app/services/github_pages_publisher.rb

class GithubPagesPublisher
  def initialize(user, page)
    @user = user
    @page = page
  end

  def publish
    result = push_to_github(html_content)

    if result[:success]
      {
        success: true,
        published_url: "https://#{page_subdomain}.#{ENV['GITHUB_PAGES_DOMAIN'] || 'thin.ly'}",
        published_at: Time.current
      }
    else
      result
    end
  end

  def unpublish
    result = delete_from_github

    if result[:success]
      { success: true }
    else
      result
    end
  end

  private

  def html_content
    # Extract links from page content
    links = page_resources

    # Generate complete static HTML using Rails templates
    html = ApplicationController.render(
      template: "link_in_bio/static",
      layout: "link_in_bio_public",
      assigns: {
        user: @user,
        page: @page,
        links: links,
        tracking_enabled: true  # Pass this flag to include tracking scripts
      }
    )

    # Clean up debug comments for production deployment
    clean_html_for_production(html)
  end

  def clean_html_for_production(html)
    # Remove Rails debug comments
    html.gsub(/<!-- BEGIN.*?-->/, "")
        .gsub(/<!-- END.*?-->/, "")
        .gsub(/\n\s*\n/, "\n")  # Remove extra blank lines
        .strip
  end

  def push_to_github(html_content)
    file_path = "#{page_subdomain}/index.html"

    begin
      # Try to get existing file
      existing_file = github_client.contents(repository, path: file_path)

      # Update existing file
      github_client.update_contents(
        repository,
        file_path,
        "Update #{@page.title} Link-in-Bio page",
        existing_file.sha,
        html_content,
        branch: "main"
      )

      { success: true }
    rescue Octokit::NotFound
      # Create new file (and directory structure)
      github_client.create_contents(
        repository,
        file_path,
        "Create #{@page.title} Link-in-Bio page",
        html_content,
        branch: "main"
      )

      { success: true }
    rescue Octokit::Error => e
      Rails.logger.error "GitHub API Error: #{e.message}"
      { success: false, error: "GitHub API Error: #{e.message}" }
    rescue StandardError => e
      Rails.logger.error "Publishing Error: #{e.message}"
      { success: false, error: "Publishing failed: #{e.message}" }
    end
  end

  def delete_from_github
    file_path = "#{page_subdomain}/index.html"

    begin
      existing_file = github_client.contents(repository, path: file_path)
      github_client.delete_contents(
        repository,
        file_path,
        "Delete #{@page.title} Link-in-Bio page",
        existing_file.sha,
        branch: "main"
      )

      { success: true }
    rescue Octokit::NotFound
      # Already deleted or never existed
      { success: true }
    rescue Octokit::Error => e
      Rails.logger.error "GitHub API Error: #{e.message}"
      { success: false, error: "GitHub API Error: #{e.message}" }
    rescue StandardError => e
      Rails.logger.error "Unpublishing Error: #{e.message}"
      { success: false, error: "Unpublishing failed: #{e.message}" }
    end
  end

  def page_subdomain
    # Generate a unique subdomain based on brand page lookup code
    @page_subdomain ||= @page.lookup_code
  end

  def repository
    @repository ||= ENV["GITHUB_PAGES_REPO"] || Rails.application.credentials.dig(:github_pages_repo) # e.g., "your-org/thin-ly-pages"
  end

  def github_client
    @github_client ||= Octokit::Client.new(access_token: ENV["GITHUB_TOKEN"] || Rails.application.credentials.dig(:github_token))
  end

  def page_resources
    # Fetch resources with their linkable associations (Links, QR Codes, etc.)
    @page_resources ||= @page.draft_version.resources.includes(:linkable).order(sort_order: :asc)
      .select { |resource| resource.linkable_type == "Link" }.map do |resource|
        linkable = resource.linkable

        OpenStruct.new(
          id: linkable.id,
          title: linkable.title || "Untitled Link",
          url: linkable.original_url || "#",
          color: resource.color || "#3b82f6",
          description: linkable.description
        )
      end
  end
end
