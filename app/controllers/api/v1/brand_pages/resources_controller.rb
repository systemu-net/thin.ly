module Api
  module V1
    module BrandPages
      class ResourcesController < ApplicationController
        before_action :authenticate_user!
        skip_before_action :verify_authenticity_token
        before_action :set_brand_page
        before_action :check_brand_page_authorization
        before_action :set_resource, only: [ :update, :destroy ]

        # GET /api/v1/brand_pages/:brand_page_lookup_code/resources
        def index
          @resources = @brand_page.resources.includes(:linkable)
          render json: {
            resources: @resources.map do |resource|
              {
                id: resource.id,
                sort_order: resource.sort_order,
                color: resource.color,
                linkable_type: resource.linkable_type,
                linkable: resource.linkable.as_json(only: [ :id, :lookup_code, :original_url, :title, :description, :created_at, :updated_at, :is_safe, :clicks_count ])
              }
            end
          }, status: :ok
        end

        # POST /api/v1/brand_pages/:brand_page_lookup_code/resources
        def create
          ActiveRecord::Base.transaction do
            # Create the link first
            @link = current_user.links.build(link_params)

            unless @link.save
              render json: { errors: @link.errors.full_messages }, status: :unprocessable_content
              raise ActiveRecord::Rollback
              return
            end

            # Create the resource (connection between brand_page and link)
            @resource = @brand_page.resources.build(
              linkable: @link,
              sort_order: resource_params[:sort_order] || next_sort_order,
              color: resource_params[:color]
            )

            unless @resource.save
              render json: { errors: @resource.errors.full_messages }, status: :unprocessable_content
              raise ActiveRecord::Rollback
              return
            end

            render json: {
              resource: {
                id: @resource.id,
                sort_order: @resource.sort_order,
                color: @resource.color,
                linkable_type: @resource.linkable_type,
                linkable: @link.as_json(only: [ :id, :lookup_code, :original_url, :title, :description, :created_at, :updated_at, :is_safe, :clicks_count ])
              }
            }, status: :created
          end
        end

        # PATCH /api/v1/brand_pages/:brand_page_lookup_code/resources/reorder
        def reorder
          resources_params = params.require(:resources)

          ActiveRecord::Base.transaction do
            resources_params.each do |resource_update|
              resource = @brand_page.resources.find(resource_update[:id])
              resource.update!(sort_order: resource_update[:sort_order])
            end
          end

          # Return all resources in the new order
          @resources = @brand_page.resources.includes(:linkable)
          render json: {
            resources: @resources.map do |resource|
              {
                id: resource.id,
                sort_order: resource.sort_order,
                color: resource.color,
                linkable_type: resource.linkable_type,
                linkable: resource.linkable.as_json(only: [ :id, :lookup_code, :original_url, :title, :description, :created_at, :updated_at, :is_safe, :clicks_count ])
              }
            end
          }, status: :ok
        rescue ActiveRecord::RecordNotFound => e
          render json: { error: "Resource not found" }, status: :not_found
        rescue ActiveRecord::RecordInvalid => e
          render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
        end

        # PATCH/PUT /api/v1/brand_pages/:brand_page_lookup_code/resources/:id
        def update
          if @resource.linkable.update(link_params)
            @resource.update(sort_order: resource_params[:sort_order]) if resource_params[:sort_order].present?
            @resource.update(color: resource_params[:color]) if resource_params[:color].present?

            render json: {
              resource: {
                id: @resource.id,
                sort_order: @resource.sort_order,
                color: @resource.color,
                linkable_type: @resource.linkable_type,
                linkable: @resource.linkable.as_json(only: [ :id, :lookup_code, :original_url, :title, :description, :created_at, :updated_at, :is_safe, :clicks_count ])
              }
            }, status: :ok
          else
            render json: { errors: @resource.linkable.errors.full_messages }, status: :unprocessable_content
          end
        end

        # DELETE /api/v1/brand_pages/:brand_page_lookup_code/resources/:id
        def destroy
          @resource.destroy
          render json: {}, status: :no_content
        end

        private

        def set_brand_page
          @brand_page = BrandPage.find_by(lookup_code: params[:brand_page_lookup_code])
          render json: { error: "Brand page not found" }, status: :not_found unless @brand_page
        end

        def check_brand_page_authorization
          unless @brand_page && current_user.id == @brand_page.user_id
            render json: { error: "Unauthorized" }, status: :unauthorized
          end
        end

        def set_resource
          @resource = @brand_page.resources.find_by(id: params[:id])
          render json: { error: "Resource not found" }, status: :not_found unless @resource
        end

        def link_params
          params.require(:link).permit(:original_url, :title, :description)
        end

        def resource_params
          params.fetch(:resource, {}).permit(:sort_order, :color)
        end

        def next_sort_order
          max_order = @brand_page.resources.unscoped.maximum(:sort_order) || -1
          max_order + 1
        end
      end
    end
  end
end
