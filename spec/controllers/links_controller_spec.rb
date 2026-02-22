require 'rails_helper'

RSpec.describe Api::V1::LinksController, type: :controller do
  let(:url) { 'https://www.thin.ly' }
  let(:valid_attributes) { { original_url: url } }
  let(:user) { create(:user) }
  let(:stripe_customer_id) { '1234' }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: stripe_customer_id))
    allow(LinkScannerJob).to receive(:perform_async).and_return(true)
    allow(QrCodeGeneratorJob).to receive(:perform_async).and_return(true)
  end

  it 'can shorten a link provided by the user' do
    sign_in(user)
    post :create, params: { link: valid_attributes }, as: :json

    link = assigns(:link)
    expect(link.original_url).to eq(url)
    expect(link.valid?).to eq(true)
    expect(link.persisted?).to eq(true)

    expect(link.lookup_code.length).to eq(7)
    expect(link.user_id).to eq(user.id)

    expect(response).to have_http_status(:created)
    expect(response).to render_template("create")
  end

  describe 'GET #index with sorting' do
    let!(:old_link) { create(:link, user: user, created_at: 3.days.ago, clicks_count: 5) }
    let!(:middle_link) { create(:link, user: user, created_at: 2.days.ago, clicks_count: 10) }
    let!(:new_link) { create(:link, user: user, created_at: 1.day.ago, clicks_count: 3) }

    before do
      sign_in(user)
    end

    context 'when sorting by created_at' do
      it 'returns links sorted by created_at descending by default' do
        get :index, params: { sort_by: 'created_at', order: 'desc' }, as: :json

        expect(response).to have_http_status(:ok)
        links = assigns(:links)
        expect(links.pluck(:id)).to eq([ new_link.id, middle_link.id, old_link.id ])
      end

      it 'returns links sorted by created_at ascending' do
        get :index, params: { sort_by: 'created_at', order: 'asc' }, as: :json

        expect(response).to have_http_status(:ok)
        links = assigns(:links)
        expect(links.pluck(:id)).to eq([ old_link.id, middle_link.id, new_link.id ])
      end
    end

    context 'when sorting by clicks_count' do
      it 'returns links sorted by clicks descending' do
        get :index, params: { sort_by: 'clicks', order: 'desc' }, as: :json

        expect(response).to have_http_status(:ok)
        links = assigns(:links)
        expect(links.pluck(:id)).to eq([ middle_link.id, old_link.id, new_link.id ])
      end

      it 'returns links sorted by clicks ascending' do
        get :index, params: { sort_by: 'clicks', order: 'asc' }, as: :json

        expect(response).to have_http_status(:ok)
        links = assigns(:links)
        expect(links.pluck(:id)).to eq([ new_link.id, old_link.id, middle_link.id ])
      end
    end

    context 'when sorting by last_clicked' do
      before do
        create(:click, link: old_link, created_at: 5.hours.ago)
        create(:click, link: middle_link, created_at: 2.hours.ago)
        create(:click, link: new_link, created_at: 1.hour.ago)
      end

      it 'returns links sorted by last_clicked descending' do
        get :index, params: { sort_by: 'last_clicked', order: 'desc' }, as: :json

        expect(response).to have_http_status(:ok)
        links = assigns(:links)
        expect(links.pluck(:id)).to eq([ new_link.id, middle_link.id, old_link.id ])
      end

      it 'returns links sorted by last_clicked ascending' do
        get :index, params: { sort_by: 'last_clicked', order: 'asc' }, as: :json

        expect(response).to have_http_status(:ok)
        links = assigns(:links)
        expect(links.pluck(:id)).to eq([ old_link.id, middle_link.id, new_link.id ])
      end
    end

    context 'when no sorting parameters provided' do
      it 'defaults to sorting by created_at descending' do
        get :index, as: :json

        expect(response).to have_http_status(:ok)
        links = assigns(:links)
        expect(links.pluck(:id)).to eq([ new_link.id, middle_link.id, old_link.id ])
      end
    end

    context 'when invalid sort parameter provided' do
      it 'defaults to sorting by created_at descending' do
        get :index, params: { sort_by: 'invalid_field', order: 'asc' }, as: :json

        expect(response).to have_http_status(:ok)
        links = assigns(:links)
        expect(links.pluck(:id)).to eq([ new_link.id, middle_link.id, old_link.id ])
      end
    end

    context 'when using sort_by parameter instead of sort' do
      it 'returns links sorted by clicks_count descending' do
        get :index, params: { sort_by: 'clicks_count', order: 'desc' }, as: :json

        expect(response).to have_http_status(:ok)
        links = assigns(:links)
        expect(links.pluck(:id)).to eq([ middle_link.id, old_link.id, new_link.id ])
      end

      it 'returns links sorted by clicks_count ascending' do
        get :index, params: { sort_by: 'clicks_count', order: 'asc' }, as: :json

        expect(response).to have_http_status(:ok)
        links = assigns(:links)
        expect(links.pluck(:id)).to eq([ new_link.id, old_link.id, middle_link.id ])
      end
    end
  end
end
