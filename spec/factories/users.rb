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
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "testuser#{n}@example.com" }
    password { 'password123' }
    terms_accepted { true }

    # Skip the Stripe customer creation in tests
    after(:build) do |user|
      user.define_singleton_method(:create_stripe_customer) { true }
      # Skip avatar generation in tests by default for performance
      user.define_singleton_method(:generate_default_avatar) { true }
    end

    trait :with_avatar do
      avatar { Rack::Test::UploadedFile.new(Rails.root.join('spec', 'fixtures', 'files', 'test_avatar.jpg'), 'image/jpeg') }
    end

    trait :with_generated_avatar do
      # Allow avatar generation for this user
      after(:build) do |user|
        user.define_singleton_method(:generate_default_avatar) do
          generator = JdenticonGenerator.new(user.email)
          user.avatar = generator.generate
        end
      end
    end
  end
end
