require 'rails_helper'

RSpec.describe "Api::V1::BrandPages", type: :request do
  let(:stripe_customer_id) { 'cus_test123' }
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:valid_attributes) do
    {
      content: { title: "Test Page", color: "blue", links: [ "https://example.com" ] },
      title: "My Brand Page",
      description: "A test brand page"
    }
  end

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: stripe_customer_id))
  end

  describe "GET /api/v1/brand_pages" do
    context "when user is authenticated" do
      before { sign_in user }

      it "returns user's draft brand pages ordered by updated_at desc" do
        draft1 = create(:brand_page, :draft, user: user, updated_at: 1.hour.ago)
        draft2 = create(:brand_page, :draft, user: user, updated_at: 30.minutes.ago)
        create(:brand_page, :published, user: user)  # Should not appear in drafts list
        create(:brand_page, :draft, user: other_user)  # Should not appear in user's list

        get "/api/v1/brand_pages", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        brand_pages = json_response['brand_pages']

        expect(brand_pages.size).to eq(2)
        expect(brand_pages.first['id']).to eq(draft2.id)
        expect(brand_pages.last['id']).to eq(draft1.id)
        expect(brand_pages.map { |bp| bp['status'] }).to all(eq('DRAFT'))
      end

      it "returns empty array when user has no draft brand pages" do
        create(:brand_page, :published, user: user)

        get "/api/v1/brand_pages", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['brand_pages']).to be_empty
      end
    end

    context "when user is not authenticated" do
      it "returns unauthorized status" do
        get "/api/v1/brand_pages"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "GET /api/v1/brand_pages/:lookup_code" do
    let(:brand_page) { create(:brand_page, :draft, user: user) }

    context "when user is authenticated and owns the brand page" do
      before { sign_in user }

      it "returns the brand page" do
        get "/api/v1/brand_pages/#{brand_page.lookup_code}", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        bp = json_response['brand_page']

        expect(bp['id']).to eq(brand_page.id)
        expect(bp['lookup_code']).to eq(brand_page.lookup_code)
        expect(bp['status']).to eq('DRAFT')
        expect(bp['has_published_version']).to be_falsey
        expect(bp['has_draft_version']).to be_falsey
      end
    end

    context "when user tries to access another user's brand page" do
      let(:other_brand_page) { create(:brand_page, :draft, user: other_user) }

      before { sign_in user }

      it "returns unauthorized status" do
        get "/api/v1/brand_pages/#{other_brand_page.lookup_code}", headers: auth_headers(user)
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when brand page doesn't exist" do
      before { sign_in user }

      it "returns not found status" do
        get "/api/v1/brand_pages/nonexistent", headers: auth_headers(user)
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when user is not authenticated" do
      it "returns unauthorized status" do
        get "/api/v1/brand_pages/#{brand_page.lookup_code}"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/brand_pages" do
    context "when user is authenticated" do
      before { sign_in user }

      it "creates a new brand page with valid attributes" do
        expect {
          post "/api/v1/brand_pages",
               params: { brand_page: valid_attributes },
               headers: auth_headers(user)
        }.to change(BrandPage, :count).by(1)

        expect(response).to have_http_status(:created)

        json_response = JSON.parse(response.body)
        bp = json_response['brand_page']

        expect(bp['content']['title']).to eq(valid_attributes[:content][:title])
        expect(bp['content']['color']).to eq(valid_attributes[:content][:color])
        expect(bp['title']).to eq(valid_attributes[:title])
        expect(bp['description']).to eq(valid_attributes[:description])
        expect(bp['status']).to eq('DRAFT')
        expect(bp['lookup_code']).to be_present
      end

      it "creates a brand page with only content (minimum required)" do
        minimal_params = { content: { title: "Minimal Page" } }

        expect {
          post "/api/v1/brand_pages",
               params: { brand_page: minimal_params },
               headers: auth_headers(user)
        }.to change(BrandPage, :count).by(1)

        expect(response).to have_http_status(:created)

        json_response = JSON.parse(response.body)
        bp = json_response['brand_page']

        expect(bp['content']['title']).to eq(minimal_params[:content][:title])
        expect(bp['title']).to eq("Untitled")  # Default value
      end

      context "with invalid attributes" do
        it "returns errors when content is missing" do
          invalid_params = { title: "Test Page" }

          post "/api/v1/brand_pages",
               params: { brand_page: invalid_params },
               headers: auth_headers(user)

          expect(response).to have_http_status(:unprocessable_entity)

          json_response = JSON.parse(response.body)
          expect(json_response['errors']).to include("Content can't be blank")
        end
      end
    end

    context "when user is not authenticated" do
      it "returns unauthorized status" do
        post "/api/v1/brand_pages", params: { brand_page: valid_attributes }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "PUT /api/v1/brand_pages/:lookup_code" do
    let(:brand_page) { create(:brand_page, :draft, user: user, content: { title: "Original" }) }
    let(:update_params) do
      {
        content: { title: "Updated Title", color: "green" },
        title: "Updated Page Title",
        description: "Updated description"
      }
    end

    context "when user is authenticated and owns the brand page" do
      before { sign_in user }

      context "when brand page is draft" do
        it "updates the brand page successfully" do
          put "/api/v1/brand_pages/#{brand_page.lookup_code}",
              params: { brand_page: update_params },
              headers: auth_headers(user)

          expect(response).to have_http_status(:ok)

          json_response = JSON.parse(response.body)
          bp = json_response['brand_page']

          expect(bp['content']['title']).to eq(update_params[:content][:title])
          expect(bp['content']['color']).to eq(update_params[:content][:color])
          expect(bp['title']).to eq(update_params[:title])
          expect(bp['description']).to eq(update_params[:description])

          # Verify database was updated
          brand_page.reload
          expect(brand_page.content['title']).to eq(update_params[:content][:title])
          expect(brand_page.title).to eq(update_params[:title])
          expect(brand_page.description).to eq(update_params[:description])
        end

        context "with partial updates" do
          it "accepts updates with only title field" do
            original_content = brand_page.content
            partial_params = { title: "Updated Title Only" }

            put "/api/v1/brand_pages/#{brand_page.lookup_code}",
                params: { brand_page: partial_params },
                headers: auth_headers(user)

            expect(response).to have_http_status(:ok)

            brand_page.reload
            expect(brand_page.content).to eq(original_content)
            expect(brand_page.title).to eq(partial_params[:title])
          end
        end
      end

      context "when brand page is published" do
        let(:published_page) { create(:brand_page, :published, user: user) }

        it "prevents updating published brand pages" do
          put "/api/v1/brand_pages/#{published_page.lookup_code}",
              params: { brand_page: update_params },
              headers: auth_headers(user)

          expect(response).to have_http_status(:unprocessable_entity)

          json_response = JSON.parse(response.body)
          expect(json_response['error']).to include("Cannot update a published brand page")
        end
      end
    end

    context "when user tries to update another user's brand page" do
      let(:other_brand_page) { create(:brand_page, :draft, user: other_user) }

      before { sign_in user }

      it "returns unauthorized status" do
        put "/api/v1/brand_pages/#{other_brand_page.lookup_code}",
            params: { brand_page: update_params },
            headers: auth_headers(user)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when user is not authenticated" do
      it "returns unauthorized status" do
        put "/api/v1/brand_pages/#{brand_page.lookup_code}",
            params: { brand_page: update_params }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "DELETE /api/v1/brand_pages/:lookup_code" do
    context "when user is authenticated and owns the brand page" do
      before { sign_in user }

      context "when deleting a draft without published version" do
        let(:draft_page) { create(:brand_page, :draft, user: user) }

        it "deletes the brand page successfully" do
          draft_page_id = draft_page.id

          expect {
            delete "/api/v1/brand_pages/#{draft_page.lookup_code}",
                   headers: auth_headers(user)
          }.to change(BrandPage, :count).by(-1)

          expect(response).to have_http_status(:no_content)
          expect(BrandPage.find_by(id: draft_page_id)).to be_nil
        end
      end
    end

    context "when user tries to delete another user's brand page" do
      let(:other_brand_page) { create(:brand_page, :draft, user: other_user) }

      before { sign_in user }

      it "returns unauthorized status" do
        delete "/api/v1/brand_pages/#{other_brand_page.lookup_code}",
               headers: auth_headers(user)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when user is not authenticated" do
      let(:brand_page) { create(:brand_page, :draft, user: user) }

      it "returns unauthorized status" do
        delete "/api/v1/brand_pages/#{brand_page.lookup_code}"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/brand_pages/:lookup_code/publish" do
    context "when user is authenticated and owns the brand page" do
      before { sign_in user }

      context "when publishing a draft for the first time" do
        let(:draft_page) { create(:brand_page, :draft, user: user) }

        it "creates a published version and updates the draft" do
          # Ensure the draft exists before counting
          draft_page
          initial_count = BrandPage.count

          post "/api/v1/brand_pages/#{draft_page.lookup_code}/publish",
               headers: auth_headers(user)

          expect(BrandPage.count).to eq(initial_count + 1)
          expect(response).to have_http_status(:ok)

          json_response = JSON.parse(response.body)
          bp = json_response['brand_page']

          # With async publishing, the status is still 'DRAFT' until the job completes
          expect(bp['status']).to eq('DRAFT')
          expect(bp['published_at']).to be_nil  # Will be set by the background job
          expect(bp['lookup_code']).not_to eq(draft_page.lookup_code)  # New lookup code for published version

          # Verify the draft now points to the published version
          draft_page.reload
          expect(draft_page.published_version).to be_present
          expect(draft_page.published_version.published?).to be_falsy  # Not published until job completes
        end
      end

      context "when publishing a draft that already has a published version" do
        let!(:existing_published) { create(:brand_page, :published, user: user, content: { title: "Old Published" }) }
        let!(:draft_with_published) { create(:brand_page, :draft, user: user, published_version: existing_published, content: { title: "New Draft Content" }) }

        it "updates the existing published version instead of creating new one" do
          original_published_id = existing_published.id
          initial_count = BrandPage.count

          post "/api/v1/brand_pages/#{draft_with_published.lookup_code}/publish",
               headers: auth_headers(user)

          expect(BrandPage.count).to eq(initial_count)
          expect(response).to have_http_status(:ok)

          json_response = JSON.parse(response.body)
          bp = json_response['brand_page']

          expect(bp['id']).to eq(original_published_id)
          expect(bp['status']).to eq('DRAFT')  # Status is DRAFT until job completes
          expect(bp['content']).to eq(draft_with_published.content)

          # Verify the published version was updated with draft content
          existing_published.reload
          expect(existing_published.content).to eq(draft_with_published.content)
        end
      end

      context "when trying to publish an already published version" do
        let(:published_page) { create(:brand_page, :published, user: user) }

        it "returns an error" do
          post "/api/v1/brand_pages/#{published_page.lookup_code}/publish",
               headers: auth_headers(user)

          expect(response).to have_http_status(:unprocessable_entity)

          json_response = JSON.parse(response.body)
          expect(json_response['error']).to include("You can only publish the draft version")
        end
      end
    end

    context "when user tries to publish another user's brand page" do
      let(:other_brand_page) { create(:brand_page, :draft, user: other_user) }

      before { sign_in user }

      it "returns unauthorized status" do
        post "/api/v1/brand_pages/#{other_brand_page.lookup_code}/publish",
             headers: auth_headers(user)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when user is not authenticated" do
      let(:draft_page) { create(:brand_page, :draft, user: user) }

      it "returns unauthorized status" do
        post "/api/v1/brand_pages/#{draft_page.lookup_code}/publish"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/brand_pages/:lookup_code/unpublish" do
    context "when user is authenticated and owns the brand page" do
      before { sign_in user }

      context "when unpublishing a published version with draft" do
        let(:published_page) { create(:brand_page, :published, user: user) }
        let(:draft_version) { create(:brand_page, :draft, user: user, published_version: published_page) }

        before do
          # Set up the relationship properly
          draft_version
          published_page.update!(draft_version: draft_version)
        end

        it "deletes the published version and returns the draft" do
          draft_id = draft_version.id
          published_id = published_page.id

          # With async unpublishing, the record is not deleted immediately
          expect {
            post "/api/v1/brand_pages/#{published_page.lookup_code}/unpublish",
                 headers: auth_headers(user)
          }.not_to change(BrandPage, :count)

          expect(response).to have_http_status(:ok)

          json_response = JSON.parse(response.body)
          bp = json_response['brand_page']

          expect(bp['id']).to eq(draft_id)
          expect(bp['status']).to eq('DRAFT')

          # Verify the unpublish job was triggered but record still exists
          # (it will be deleted when the background job completes)
          expect(BrandPage.find_by(id: published_id)).to be_present
          draft_version.reload
          expect(draft_version.published_version).to be_nil  # This is updated immediately
        end
      end

      context "when trying to unpublish a draft version" do
        let(:draft_page) { create(:brand_page, :draft, user: user) }

        it "returns an error" do
          post "/api/v1/brand_pages/#{draft_page.lookup_code}/unpublish",
               headers: auth_headers(user)

          expect(response).to have_http_status(:unprocessable_entity)

          json_response = JSON.parse(response.body)
          expect(json_response['error']).to include("You can only unpublish the published version")
        end
      end
    end

    context "when user tries to unpublish another user's brand page" do
      let(:other_published_page) { create(:brand_page, :published, user: other_user) }

      before { sign_in user }

      it "returns unauthorized status" do
        post "/api/v1/brand_pages/#{other_published_page.lookup_code}/unpublish",
             headers: auth_headers(user)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when user is not authenticated" do
      let(:published_page) { create(:brand_page, :published, user: user) }

      it "returns unauthorized status" do
        post "/api/v1/brand_pages/#{published_page.lookup_code}/unpublish"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
