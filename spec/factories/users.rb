# spec/factories/users.rb

FactoryBot.define do
  factory :user do
    email { 'testuser@example.com' }
    password { 'password' }
    # Add additional fields as necessary
  end
end
