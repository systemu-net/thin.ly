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
