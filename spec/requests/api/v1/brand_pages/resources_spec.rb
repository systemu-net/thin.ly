require 'rails_helper'

RSpec.describe "Api::V1::BrandPages::Resources", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let!(:brand_page) { create(:brand_page, user: user).tap(&:reload) }
  let!(:other_brand_page) { create(:brand_page, user: other_user).tap(&:reload) }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_test123'))
  end

  describe "GET /api/v1/brand_pages/:brand_page_lookup_code/resources" do
    context "when user is authenticated and owns the brand page" do
      before { sign_in(user) }

      it "returns all links for the brand page ordered by sort_order" do
        link1 = create(:link, user: user, original_url: "https://example1.com")
        link2 = create(:link, user: user, original_url: "https://example2.com")
        link3 = create(:link, user: user, original_url: "https://example3.com")

        create(:resource, page: brand_page, linkable: link1, sort_order: 2)
        create(:resource, page: brand_page, linkable: link2, sort_order: 0)
        create(:resource, page: brand_page, linkable: link3, sort_order: 1)

        get "/api/v1/brand_pages/#{brand_page.lookup_code}/resources"

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['resources'].size).to eq(3)
        expect(json_response['resources'][0]['sort_order']).to eq(0)
        expect(json_response['resources'][1]['sort_order']).to eq(1)
        expect(json_response['resources'][2]['sort_order']).to eq(2)
      end

      it "returns empty array when brand page has no links" do
        get "/api/v1/brand_pages/#{brand_page.lookup_code}/resources"

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['resources']).to be_empty
      end

      it "includes is_safe and clicks_count in the response" do
        link = create(:link, user: user, original_url: "https://example.com", is_safe: true)
        create_list(:click, 5, link: link)
        create(:resource, page: brand_page, linkable: link, sort_order: 0)

        get "/api/v1/brand_pages/#{brand_page.lookup_code}/resources"

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        resource = json_response['resources'].first
        expect(resource['linkable']['is_safe']).to eq(true)
        expect(resource['linkable']['clicks_count']).to eq(5)
      end
    end

    context "when user is not authenticated" do
      it "returns unauthorized status" do
        get "/api/v1/brand_pages/#{brand_page.lookup_code}/resources"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when user tries to access another user's brand page" do
      before { sign_in(user) }

      it "returns unauthorized status" do
        get "/api/v1/brand_pages/#{other_brand_page.lookup_code}/resources"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/brand_pages/:brand_page_lookup_code/resources" do
    context "when user is authenticated and owns the brand page" do
      before { sign_in(user) }

      it "creates a new link and associates it with the brand page" do
        expect {
          post "/api/v1/brand_pages/#{brand_page.lookup_code}/resources", params: {
            link: {
              original_url: "https://example.com",
              title: "Example Link",
              description: "A test link"
            }
          }
        }.to change(Link, :count).by(1).and change(Resource, :count).by(1)

        expect(response).to have_http_status(:created)
        json_response = JSON.parse(response.body)
        expect(json_response['resource']['linkable']['original_url']).to eq("https://example.com")
        expect(json_response['resource']['linkable']['title']).to eq("Example Link")
        expect(json_response['resource']['sort_order']).to eq(0)
      end

      it "auto-assigns sort_order if not provided" do
        link1 = create(:link, user: user)
        create(:resource, page: brand_page, linkable: link1, sort_order: 5)

        post "/api/v1/brand_pages/#{brand_page.lookup_code}/resources", params: {
          link: { original_url: "https://example.com" }
        }

        json_response = JSON.parse(response.body)
        expect(json_response['resource']['sort_order']).to eq(6)
      end

      it "includes is_safe and clicks_count in created resource" do
        post "/api/v1/brand_pages/#{brand_page.lookup_code}/resources", params: {
          link: {
            original_url: "https://example.com",
            title: "Example Link"
          }
        }

        expect(response).to have_http_status(:created)
        json_response = JSON.parse(response.body)
        expect(json_response['resource']['linkable']).to have_key('is_safe')
        expect(json_response['resource']['linkable']['clicks_count']).to eq(0)
      end

      it "allows custom sort_order" do
        post "/api/v1/brand_pages/#{brand_page.lookup_code}/resources", params: {
          link: { original_url: "https://example.com" },
          resource: { sort_order: 10 }
        }

        json_response = JSON.parse(response.body)
        expect(json_response['resource']['sort_order']).to eq(10)
      end

      it "returns error for invalid link data" do
        post "/api/v1/brand_pages/#{brand_page.lookup_code}/resources", params: {
          link: { original_url: "invalid-url" }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to be_present
      end
    end

    context "when user is not authenticated" do
      it "returns unauthorized status" do
        post "/api/v1/brand_pages/#{brand_page.lookup_code}/resources", params: {
          link: { original_url: "https://example.com" }
        }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "PATCH /api/v1/brand_pages/:brand_page_lookup_code/resources/reorder" do
    context "when user is authenticated and owns the brand page" do
      before { sign_in(user) }

      it "reorders resources" do
        link1 = create(:link, user: user)
        link2 = create(:link, user: user)
        link3 = create(:link, user: user)

        resource1 = create(:resource, page: brand_page, linkable: link1, sort_order: 0)
        resource2 = create(:resource, page: brand_page, linkable: link2, sort_order: 1)
        resource3 = create(:resource, page: brand_page, linkable: link3, sort_order: 2)

        patch "/api/v1/brand_pages/#{brand_page.lookup_code}/resources/reorder", params: {
          resources: [
            { id: resource1.id, sort_order: 2 },
            { id: resource2.id, sort_order: 0 },
            { id: resource3.id, sort_order: 1 }
          ]
        }

        expect(response).to have_http_status(:ok)

        expect(resource1.reload.sort_order).to eq(2)
        expect(resource2.reload.sort_order).to eq(0)
        expect(resource3.reload.sort_order).to eq(1)
      end

      it "returns error for non-existent resource" do
        patch "/api/v1/brand_pages/#{brand_page.lookup_code}/resources/reorder", params: {
          resources: [ { id: 99999, sort_order: 0 } ]
        }

        expect(response).to have_http_status(:not_found)
      end

      it "includes is_safe and clicks_count in reordered resources" do
        link = create(:link, user: user, is_safe: false)
        create_list(:click, 3, link: link)
        resource = create(:resource, page: brand_page, linkable: link, sort_order: 0)

        patch "/api/v1/brand_pages/#{brand_page.lookup_code}/resources/reorder", params: {
          resources: [ { id: resource.id, sort_order: 1 } ]
        }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        returned_resource = json_response['resources'].first
        expect(returned_resource['linkable']['is_safe']).to eq(false)
        expect(returned_resource['linkable']['clicks_count']).to eq(3)
      end
    end
  end

  describe "PATCH /api/v1/brand_pages/:brand_page_lookup_code/resources/:id" do
    context "when user is authenticated and owns the brand page" do
      before { sign_in(user) }

      it "updates the link" do
        link = create(:link, user: user, original_url: "https://old.com")
        resource = create(:resource, page: brand_page, linkable: link, sort_order: 1)

        patch "/api/v1/brand_pages/#{brand_page.lookup_code}/resources/#{resource.id}", params: {
          link: {
            original_url: "https://new.com",
            title: "Updated Title"
          }
        }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['resource']['linkable']['original_url']).to eq("https://new.com")
        expect(json_response['resource']['linkable']['title']).to eq("Updated Title")
      end

      it "updates sort_order if provided" do
        link = create(:link, user: user)
        resource = create(:resource, page: brand_page, linkable: link, sort_order: 1)

        patch "/api/v1/brand_pages/#{brand_page.lookup_code}/resources/#{resource.id}", params: {
          link: { original_url: "https://example.com" },
          resource: { sort_order: 5 }
        }

        expect(response).to have_http_status(:ok)
        expect(resource.reload.sort_order).to eq(5)
      end

      it "includes is_safe and clicks_count in updated resource" do
        link = create(:link, user: user, original_url: "https://old.com", is_safe: true)
        create_list(:click, 7, link: link)
        resource = create(:resource, page: brand_page, linkable: link, sort_order: 1)

        patch "/api/v1/brand_pages/#{brand_page.lookup_code}/resources/#{resource.id}", params: {
          link: { title: "Updated Title" }
        }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['resource']['linkable']['is_safe']).to eq(true)
        expect(json_response['resource']['linkable']['clicks_count']).to eq(7)
      end
    end
  end

  describe "DELETE /api/v1/brand_pages/:brand_page_lookup_code/resources/:id" do
    context "when user is authenticated and owns the brand page" do
      before { sign_in(user) }

      it "deletes the resource and the link" do
        link = create(:link, user: user)
        resource = create(:resource, page: brand_page, linkable: link)

        expect {
          delete "/api/v1/brand_pages/#{brand_page.lookup_code}/resources/#{resource.id}"
        }.to change(Resource, :count).by(-1)

        expect(response).to have_http_status(:no_content)
      end

      it "returns error for non-existent resource" do
        delete "/api/v1/brand_pages/#{brand_page.lookup_code}/resources/99999"
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
