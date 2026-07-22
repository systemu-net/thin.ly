# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
#  avatar                 :string
#  email                  :string           default(""), not null
#  encrypted_password     :string           default(""), not null
#  jti                    :string           not null
#  last_country           :string
#  last_seen_at           :datetime
#  provider               :string
#  remember_created_at    :datetime
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  role                   :string           default("member"), not null
#  signup_attribution     :jsonb
#  terms_accepted         :boolean          default(FALSE), not null
#  terms_accepted_at      :datetime
#  terms_accepted_version :string
#  uid                    :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  levelcode_stripe_id    :string
#  stripe_id              :string
#
# Indexes
#
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_jti                   (jti) UNIQUE
#  index_users_on_last_seen_at          (last_seen_at)
#  index_users_on_levelcode_stripe_id   (levelcode_stripe_id) UNIQUE WHERE (levelcode_stripe_id IS NOT NULL)
#  index_users_on_provider_and_uid      (provider,uid) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#
require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    it 'requires email' do
      user = build(:user, email: nil)
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("can't be blank")
    end

    it 'requires a unique email' do
      create(:user, email: 'duplicate@example.com')
      user = build(:user, email: 'duplicate@example.com')
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include('has already been taken')
    end

    it 'requires password on create' do
      user = build(:user, password: nil)
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("can't be blank")
    end

    it 'requires terms_accepted on create' do
      user = build(:user, terms_accepted: false)
      expect(user).not_to be_valid
      expect(user.errors[:terms_accepted]).to include('must be accepted')
    end

    it 'is valid with valid attributes' do
      user = build(:user)
      expect(user).to be_valid
    end
  end

  describe 'associations' do
    let(:user) { create(:user) }

    it 'has many links' do
      assoc = described_class.reflect_on_association(:links)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end

    it 'has many link_campaigns' do
      assoc = described_class.reflect_on_association(:link_campaigns)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end

    it 'has many qr_codes' do
      assoc = described_class.reflect_on_association(:qr_codes)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end

    it 'has many subscriptions' do
      assoc = described_class.reflect_on_association(:subscriptions)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end

    it 'has many plans through subscriptions' do
      assoc = described_class.reflect_on_association(:plans)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:through]).to eq(:subscriptions)
    end

    it 'has many brand_pages' do
      assoc = described_class.reflect_on_association(:brand_pages)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end
  end

  describe 'callbacks' do
    it 'creates a default subscription on creation' do
      user = create(:user)
      expect(user.subscriptions.count).to eq(1)
    end

    it 'creates a default Free plan via subscription' do
      user = create(:user)
      expect(user.plan).to be_present
      expect(user.plan.name).to eq('Free')
    end

    it 'creates a default campaign on creation' do
      user = create(:user)

      expect(user.link_campaigns.count).to eq(1)
      expect(user.link_campaigns.first.default).to be true
    end
  end

  describe '#plan' do
    it 'returns the first plan across subscriptions' do
      user = create(:user)
      expect(user.plan).to eq(user.plans.first)
    end
  end

  describe '#subscribed?' do
    it 'returns false when no active subscriptions' do
      user = create(:user)
      expect(user.subscribed?).to be false
    end

    it 'returns true when an active subscription exists' do
      user = create(:user)
      user.subscriptions.first.update!(status: 'active')
      expect(user.subscribed?).to be true
    end
  end

  describe 'devise' do
    it 'authenticates with correct password' do
      user = create(:user, password: 'securepassword123')
      expect(user.valid_password?('securepassword123')).to be true
    end

    it 'rejects incorrect password' do
      user = create(:user, password: 'securepassword123')
      expect(user.valid_password?('wrongpassword')).to be false
    end

    it 'generates a JTI on creation' do
      user = create(:user)
      expect(user.jti).to be_present
    end
  end

  describe 'terms acceptance audit' do
    it 'stamps terms_accepted_at and terms_accepted_version on create when accepted' do
      before_create = Time.current
      user = create(:user)

      expect(user.terms_accepted).to be true
      expect(user.terms_accepted_at).to be_present
      expect(user.terms_accepted_at).to be >= before_create
      expect(user.terms_accepted_version).to eq(User::TERMS_VERSION)
    end

    it 'does not stamp audit fields if terms were not accepted' do
      user = build(:user, terms_accepted: false)
      user.valid?
      expect(user.terms_accepted_at).to be_nil
      expect(user.terms_accepted_version).to be_nil
    end

    it 'preserves an explicitly-set acceptance time and version' do
      explicit_time = 1.year.ago
      explicit_version = "2025-01-01"
      user = create(:user, terms_accepted_at: explicit_time, terms_accepted_version: explicit_version)

      expect(user.terms_accepted_at).to be_within(1.second).of(explicit_time)
      expect(user.terms_accepted_version).to eq(explicit_version)
    end
  end
end
