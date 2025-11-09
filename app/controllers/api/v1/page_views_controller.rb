class Api::V1::PageViewsController < ApplicationController
  before_action :authenticate_user!

  # GET /api/v1/page_views
  # Get all page views for the current user's brand pages
  def index
    brand_page_ids = current_user.brand_pages.pluck(:id)
    page = params[:page]&.to_i || 1
    per_page = params[:per_page]&.to_i || 50
    offset = (page - 1) * per_page

    @page_views = PageView.where(brand_page_id: brand_page_ids)
                          .includes(:brand_page)
                          .recent
                          .limit(per_page)
                          .offset(offset)

    total_count = PageView.where(brand_page_id: brand_page_ids).count

    render json: {
      page_views: @page_views.map { |pv| page_view_json(pv) },
      meta: {
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: (total_count.to_f / per_page).ceil
      }
    }
  end

  # GET /api/v1/page_views/by_brand_page?lookup_code=abc123
  # Get page views for a specific brand page
  def by_brand_page
    lookup_code = params[:lookup_code]

    unless lookup_code.present?
      return render json: { error: "lookup_code parameter is required" }, status: :bad_request
    end

    brand_page = current_user.brand_pages.find_by(lookup_code: lookup_code)

    unless brand_page
      return render json: { error: "Brand page not found" }, status: :not_found
    end

    page = params[:page]&.to_i || 1
    per_page = params[:per_page]&.to_i || 50
    offset = (page - 1) * per_page

    @page_views = brand_page.page_views
                            .recent
                            .limit(per_page)
                            .offset(offset)

    total_count = brand_page.page_views.count

    render json: {
      page_views: @page_views.map { |pv| page_view_json(pv) },
      brand_page: {
        lookup_code: brand_page.lookup_code,
        title: brand_page.title,
        status: brand_page.status
      },
      meta: {
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: (total_count.to_f / per_page).ceil
      }
    }
  end

  private

  def page_view_json(page_view)
    {
      id: page_view.id,
      brand_page_lookup_code: page_view.brand_page.lookup_code,
      ip_address: page_view.ip_address,
      user_agent: page_view.user_agent,
      referrer: page_view.referrer,
      country: page_view.country,
      city: page_view.city,
      region: page_view.region,
      browser: page_view.browser,
      browser_version: page_view.browser_version,
      os: page_view.os,
      os_version: page_view.os_version,
      device_type: page_view.device_type,
      visited_at: page_view.visited_at,
      created_at: page_view.created_at
    }
  end
end
