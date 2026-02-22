# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
#  avatar                 :string
#  email                  :string           default(""), not null
#  encrypted_password     :string           default(""), not null
#  jti                    :string           not null
#  remember_created_at    :datetime
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  terms_accepted         :boolean          default(FALSE), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  stripe_id              :string
#
# Indexes
#
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_jti                   (jti) UNIQUE
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
end
