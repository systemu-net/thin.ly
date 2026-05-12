require 'rails_helper'

RSpec.describe 'Api::V1::Analytics', type: :request do
  let!(:user) { create(:user) }
  let!(:other_user) { create(:user) }
  let(:headers) { auth_headers(user).merge('Content-Type' => 'application/json') }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_test'))
  end

  describe 'GET /api/v1/analytics/clicks_timeline' do
    let!(:my_link) { create(:link, user: user) }
    let!(:other_link) { create(:link, user: other_user) }

    context 'with mixed clicks across windows' do
      before do
        create(:click, link: my_link, created_at: 1.day.ago)
        create(:click, link: my_link, created_at: 2.days.ago)
        # Other user's click — must NOT be counted
        create(:click, link: other_link, created_at: 1.day.ago)
        # Outside any default window
        create(:click, link: my_link, created_at: 40.days.ago)
      end

      it 'returns a 7-day series by default scoped to the current user' do
        get '/api/v1/analytics/clicks_timeline', headers: headers

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)

        expect(body['period']).to eq('7d')
        expect(body['granularity']).to eq('day')
        expect(body['points'].size).to eq(7)
        expect(body['total_clicks']).to eq(2)
      end

      it 'returns 24 hourly buckets for period=24h' do
        get '/api/v1/analytics/clicks_timeline', params: { period: '24h' }, headers: headers
        body = JSON.parse(response.body)
        expect(body['period']).to eq('24h')
        expect(body['granularity']).to eq('hour')
        expect(body['points'].size).to eq(24)
      end

      it 'returns 30 daily buckets for period=30d' do
        get '/api/v1/analytics/clicks_timeline', params: { period: '30d' }, headers: headers
        body = JSON.parse(response.body)
        expect(body['period']).to eq('30d')
        expect(body['granularity']).to eq('day')
        expect(body['points'].size).to eq(30)
      end

      it 'returns 12 monthly buckets for period=all' do
        get '/api/v1/analytics/clicks_timeline', params: { period: 'all' }, headers: headers
        body = JSON.parse(response.body)
        expect(body['period']).to eq('all')
        expect(body['granularity']).to eq('month')
        expect(body['points'].size).to eq(12)
      end

      it 'rejects unauthenticated requests' do
        get '/api/v1/analytics/clicks_timeline'
        expect(response).to have_http_status(:unauthorized)
      end

      it 'falls back to 7d on an unknown period' do
        get '/api/v1/analytics/clicks_timeline', params: { period: 'garbage' }, headers: headers
        body = JSON.parse(response.body)
        expect(body['period']).to eq('7d')
      end
    end

    # ── Bucket placement & range correctness ─────────────────────────────────
    #
    # These pin the rightmost-bucket-is-NOW invariant and verify that clicks
    # land in the correct bucket (the previous broken implementation had the
    # current day/hour/month missing entirely).

    context 'bucket placement for period=7d' do
      it "places today's click in the rightmost (last) bucket" do
        create(:click, link: my_link, created_at: Time.current)

        get '/api/v1/analytics/clicks_timeline', params: { period: '7d' }, headers: headers
        body = JSON.parse(response.body)
        points = body['points']

        expect(points.size).to eq(7)
        expect(points.last['clicks']).to eq(1)
        expect(points.first['clicks']).to eq(0)
        expect(body['total_clicks']).to eq(1)
      end

      it "places a click from 3 days ago in the 4th-from-the-end bucket" do
        create(:click, link: my_link, created_at: 3.days.ago)

        get '/api/v1/analytics/clicks_timeline', params: { period: '7d' }, headers: headers
        body = JSON.parse(response.body)
        points = body['points']

        # 7 buckets indexed 0..6, today is index 6, 3 days ago is index 3
        expect(points[3]['clicks']).to eq(1)
        points.each_with_index do |p, i|
          next if i == 3
          expect(p['clicks']).to eq(0), "expected bucket #{i} to be empty, got #{p['clicks']}"
        end
      end

      it 'includes the current partial day in total_clicks' do
        # Click 5 minutes ago — must be counted
        create(:click, link: my_link, created_at: 5.minutes.ago)

        get '/api/v1/analytics/clicks_timeline', params: { period: '7d' }, headers: headers
        body = JSON.parse(response.body)
        expect(body['total_clicks']).to eq(1)
        expect(body['points'].last['clicks']).to eq(1)
      end
    end

    context 'bucket placement for period=24h' do
      it 'places a click within the current hour in the last bucket' do
        create(:click, link: my_link, created_at: Time.current)

        get '/api/v1/analytics/clicks_timeline', params: { period: '24h' }, headers: headers
        body = JSON.parse(response.body)
        points = body['points']

        expect(points.size).to eq(24)
        expect(points.last['clicks']).to eq(1)
        expect(body['total_clicks']).to eq(1)
      end

      it 'excludes clicks older than 24 hours' do
        create(:click, link: my_link, created_at: 25.hours.ago)

        get '/api/v1/analytics/clicks_timeline', params: { period: '24h' }, headers: headers
        body = JSON.parse(response.body)
        expect(body['total_clicks']).to eq(0)
      end
    end

    context 'bucket placement for period=30d' do
      it 'places a click 29 days ago somewhere in the oldest buckets, not lost' do
        create(:click, link: my_link, created_at: 29.days.ago)
        create(:click, link: my_link, created_at: Time.current)

        get '/api/v1/analytics/clicks_timeline', params: { period: '30d' }, headers: headers
        body = JSON.parse(response.body)

        expect(body['total_clicks']).to eq(2)
        expect(body['points'].last['clicks']).to eq(1)
        # The 29-days-ago click must fall in one of the first ~2 buckets
        # (allowing for "now" being late in the day vs. exactly 29 days back).
        early = body['points'].first(3).sum { |p| p['clicks'] }
        expect(early).to be >= 1
      end

      it 'excludes a click 31 days ago' do
        create(:click, link: my_link, created_at: 31.days.ago)

        get '/api/v1/analytics/clicks_timeline', params: { period: '30d' }, headers: headers
        body = JSON.parse(response.body)
        expect(body['total_clicks']).to eq(0)
      end
    end

    context 'bucket placement for period=all' do
      it 'places a click in the current month in the last bucket' do
        create(:click, link: my_link, created_at: Time.current)

        get '/api/v1/analytics/clicks_timeline', params: { period: 'all' }, headers: headers
        body = JSON.parse(response.body)

        expect(body['points'].size).to eq(12)
        expect(body['points'].last['clicks']).to eq(1)
      end

      it 'places a click from 11 months ago somewhere in the earliest bucket(s)' do
        create(:click, link: my_link, created_at: 11.months.ago)

        get '/api/v1/analytics/clicks_timeline', params: { period: 'all' }, headers: headers
        body = JSON.parse(response.body)

        expect(body['total_clicks']).to eq(1)
        # First 2 monthly buckets should hold the 11-month-old click
        early = body['points'].first(2).sum { |p| p['clicks'] }
        expect(early).to eq(1)
      end

      it 'excludes a click 13 months ago' do
        create(:click, link: my_link, created_at: 13.months.ago)

        get '/api/v1/analytics/clicks_timeline', params: { period: 'all' }, headers: headers
        body = JSON.parse(response.body)
        expect(body['total_clicks']).to eq(0)
      end
    end

    context 'every point has a starts_at and label' do
      it 'returns iso8601 starts_at strings sorted ascending' do
        get '/api/v1/analytics/clicks_timeline', params: { period: '7d' }, headers: headers
        body = JSON.parse(response.body)

        starts = body['points'].map { |p| Time.parse(p['starts_at']) }
        expect(starts).to eq(starts.sort)
        body['points'].each do |p|
          expect(p['at']).to be_a(String)
          expect(p['at']).not_to be_empty
        end
      end
    end
  end
end
