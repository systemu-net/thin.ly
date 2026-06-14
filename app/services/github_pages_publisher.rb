# app/services/github_pages_publisher.rb
require "net/http"
require "base64"

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
    html =
      if (@page.content || {})["template"] == "portfolio"
        # The portfolio template is a self-contained document (its own <html>).
        ApplicationController.render(
          template: "link_in_bio/portfolio",
          layout: false,
          assigns: { user: @user, page: @page }
        )
      else
        ApplicationController.render(
          template: "link_in_bio/static",
          layout: "link_in_bio_public",
          assigns: {
            user: @user,
            page: @page,
            links: page_resources,
            tracking_enabled: true
          }
        )
      end

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
    return { success: false, error: "GITHUB_PAGES_REPO is not configured" } if repository.blank?
    return { success: false, error: "GITHUB_TOKEN is not configured" } if github_token.blank?

    file_path = "#{page_subdomain}/index.html"
    encoded_content = Base64.strict_encode64(html_content)

    get = github_api_request(:get, "/contents/#{file_path}?ref=#{branch}")

    if get[:status] == 200
      sha = get[:body]["sha"]
      put = github_api_request(:put, "/contents/#{file_path}", {
        message: "Update #{@page.title} Link-in-Bio page",
        content: encoded_content,
        sha: sha,
        branch: branch
      })
      put[:status].in?([ 200, 201 ]) ? { success: true } : { success: false, error: "GitHub API Error: #{put[:body]['message']}" }
    elsif get[:status] == 404
      put = github_api_request(:put, "/contents/#{file_path}", {
        message: "Create #{@page.title} Link-in-Bio page",
        content: encoded_content,
        branch: branch
      })
      put[:status].in?([ 200, 201 ]) ? { success: true } : { success: false, error: "GitHub API Error: #{put[:body]['message']}" }
    else
      { success: false, error: "GitHub API Error: #{get[:body]['message']}" }
    end
  rescue => e
    Rails.logger.error "Publishing Error: #{e.class}: #{e.message}"
    { success: false, error: "Publishing failed: #{e.message}" }
  end

  def delete_from_github
    return { success: false, error: "GITHUB_PAGES_REPO is not configured" } if repository.blank?
    return { success: false, error: "GITHUB_TOKEN is not configured" } if github_token.blank?

    file_path = "#{page_subdomain}/index.html"

    get = github_api_request(:get, "/contents/#{file_path}?ref=#{branch}")

    if get[:status] == 200
      sha = get[:body]["sha"]
      del = github_api_request(:delete, "/contents/#{file_path}", {
        message: "Delete #{@page.title} Link-in-Bio page",
        sha: sha,
        branch: branch
      })
      [ 200, 201, 204 ].include?(del[:status]) ? { success: true } : { success: false, error: "GitHub API Error: #{del[:body]['message']}" }
    elsif get[:status] == 404
      { success: true }
    else
      { success: false, error: "GitHub API Error: #{get[:body]['message']}" }
    end
  rescue => e
    Rails.logger.error "Unpublishing Error: #{e.class}: #{e.message}"
    { success: false, error: "Unpublishing failed: #{e.message}" }
  end

  def page_subdomain
    # Generate a unique subdomain based on brand page lookup code
    @page_subdomain ||= @page.lookup_code
  end

  def repository
    @repository ||= ENV["GITHUB_PAGES_REPO"] || Rails.application.credentials.dig(:github_pages_repo) # e.g., "your-org/thin-ly-pages"
  end

  def branch
    @branch ||= ENV["GITHUB_PAGES_BRANCH"].presence || "main"
  end

  def github_token
    @github_token ||= ENV["GITHUB_TOKEN"] || Rails.application.credentials.dig(:github_token)
  end

  def github_api_request(method, path, body = nil)
    uri = URI("https://api.github.com/repos/#{repository}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = case method
    when :get    then Net::HTTP::Get.new(uri)
    when :put    then Net::HTTP::Put.new(uri)
    when :delete then Net::HTTP::Delete.new(uri)
    end

    req["Authorization"]  = "Bearer #{github_token}"
    req["Accept"]         = "application/vnd.github.v3+json"
    req["Content-Type"]   = "application/json"
    req["User-Agent"]     = "thin.ly/1.0"
    req.body = body.to_json if body

    response = http.request(req)
    response_body = response.body.present? ? JSON.parse(response.body) : {}
    { status: response.code.to_i, body: response_body }
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
