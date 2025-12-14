# User Avatar Upload Feature - Implementation Summary

## Overview
Successfully implemented user avatar/profile photo upload functionality using CarrierWave with AWS S3 storage, matching your existing QR code upload pattern.

## What Was Implemented

### 1. Database Migration
- **File**: `db/migrate/20251130172855_add_avatar_to_users.rb`
- Added `avatar:string` column to `users` table
- Stores the S3 URL of the uploaded avatar

### 2. Avatar Uploader
- **File**: `app/uploaders/avatar_uploader.rb`
- Uses CarrierWave with AWS S3 (fog storage) in production/development
- Uses local file storage in test environment
- Generates unique filenames with secure tokens
- Supports image formats: jpg, jpeg, gif, png, webp
- Auto-configured to use your existing S3 credentials from `config/initializers/carrierwave.rb`

### 3. User Model
- **File**: `app/models/user.rb`
- Added `mount_uploader :avatar, AvatarUploader`
- Avatar URL accessible via `user.avatar.url`

### 4. API Endpoints

#### New Users Controller
**File**: `app/controllers/api/v1/users_controller.rb`

- **GET /api/v1/user** - Get current user profile with avatar
- **PATCH /api/v1/user** - Update user profile (including avatar)
- **PATCH /api/v1/user/avatar** - Upload/update avatar specifically
- **DELETE /api/v1/user/avatar** - Remove avatar

#### Updated Registrations Controller
**File**: `app/controllers/users/registrations_controller.rb`

- Permits `avatar`, `avatar_cache` on signup (POST /users)
- Permits `avatar`, `avatar_cache`, `remove_avatar` on account update

### 5. JSON Responses
All user JSON responses now include `avatar_url` when present:

- **POST /users** (registration) - includes `avatar_url` in user object
- **POST /users/sign_in** (login) - includes `avatar_url` in user object
- **GET /api/v1/user** - includes `avatar_url` directly
- **GET /api/v1/current_user** - includes `avatar_url` in nested `user` object with `role` and `plan` details

**Note:** The `/api/v1/current_user` endpoint returns a comprehensive user object nested under `user` key, including:
- Basic info: `id`, `email`, `created_at`, `updated_at`, `jti`
- Avatar: `avatar_url` (S3 URL or null if auto-generated/not uploaded)
- Authorization: `role` (e.g., "admin", "user")
- Subscription: `plan` object with `name` and `features` array

### 6. Routes
**File**: `config/routes.rb`

```ruby
namespace :api do
  namespace :v1 do
    resource :user, only: %i[show update] do
      patch :avatar, action: :update_avatar
      delete :avatar, action: :destroy_avatar
    end
  end
end
```

### 7. Comprehensive Tests
**File**: `spec/requests/api/v1/users_spec.rb`

- 12 test examples covering all avatar operations
- All tests passing (209 total examples, 0 failures)

## API Usage Examples

### 1. Upload Avatar During Signup
```bash
POST /users
Content-Type: multipart/form-data

{
  "user": {
    "email": "user@example.com",
    "password": "password123",
    "terms_accepted": true,
    "avatar": <file>
  }
}

Response:
{
  "user": {
    "id": 1,
    "email": "user@example.com",
    "avatar_url": "https://your-bucket.s3.amazonaws.com/uploads/user/avatar/1/avatar_abc123.jpg",
    "jti": "...",
    "created_at": "...",
    "updated_at": "..."
  }
}
```

### 2. Update Avatar for Logged-in User
```bash
PATCH /api/v1/user/avatar
Authorization: Bearer <token>
Content-Type: multipart/form-data

{
  "avatar": <file>
}

Response:
{
  "message": "Avatar uploaded successfully",
  "avatar_url": "https://your-bucket.s3.amazonaws.com/uploads/user/avatar/1/avatar_xyz789.jpg"
}
```

### 3. Get Current User with Avatar
```bash
GET /api/v1/current_user
Authorization: Bearer <token>

Response:
{
  "user": {
    "id": 19,
    "email": "test123@example.com",
    "created_at": "2025-11-30T18:24:10.013Z",
    "updated_at": "2025-11-30T18:30:01.891Z",
    "jti": "96277588-df7d-4e9e-90cd-37428f15513d",
    "avatar_url": "http://thinly.s3.amazonaws.com/uploads/user/avatar/19/avatar_035228ed-c145-4c39-95aa-29bb684bc6c6.jpg",
    "role": "admin",
    "plan": {
      "name": "Free",
      "features": [
        {"name": "links", "limit": 50, "used": 0},
        {"name": "qr_codes", "limit": 5, "used": 0},
        {"name": "brand_pages", "limit": 1, "used": 0}
      ]
    }
  }
}
```

### 4. Remove Avatar
```bash
DELETE /api/v1/user/avatar
Authorization: Bearer <token>

Response:
{
  "message": "Avatar removed successfully"
}
```

### 5. Update User Profile (including avatar)
```bash
PATCH /api/v1/user
Authorization: Bearer <token>
Content-Type: multipart/form-data

{
  "user": {
    "avatar": <file>
  }
}

Response:
{
  "id": 1,
  "email": "user@example.com",
  "avatar_url": "https://your-bucket.s3.amazonaws.com/uploads/user/avatar/1/avatar_new123.jpg",
  ...
}
```

## Usage in Brand Pages

The `avatar_url` is now available in your user object and can be used as the `profileImage` in your brand pages:

```javascript
// Frontend example - Using user's avatar in brand page

// 1. Fetch current user with avatar
const response = await fetch('http://localhost:3000/api/v1/current_user', {
  headers: { 'Authorization': `Bearer ${authToken}` }
});
const data = await response.json();
const currentUser = data.user; // Extract user from nested response

// 2. Use avatar_url in brand page content
const brandPageContent = {
  button: "rounded",
  social: {
    fb: "https://www.facebook.com/...",
    linkedin: "https://www.linkedin.com/in/..."
  },
  textColor: "#fff",
  fontFamily: "rubik",
  buttonColor: "#596289",
  gradientEnd: "#d8b0c8",
  profileImage: currentUser.avatar_url, // ← Use user's uploaded avatar from S3
  gradientStart: "#5b90bc",
  backgroundType: "gradient",
  gradientDirection: "to bottom"
};

// currentUser object structure:
// {
//   id: 19,
//   email: "test123@example.com",
//   avatar_url: "http://thinly.s3.amazonaws.com/uploads/user/avatar/19/avatar_035228ed-c145-4c39-95aa-29bb684bc6c6.jpg",
//   role: "admin",
//   plan: { name: "Free", features: [...] }
// }
```

## S3 Storage Details

- **Storage Path**: `uploads/user/avatar/{user_id}/avatar_{secure_token}.{extension}`
- **Credentials**: Uses existing AWS credentials from `config/initializers/carrierwave.rb`
- **Test Environment**: Uses local file storage (no S3 calls during testing)
- **Production/Development**: Uses AWS S3 fog storage

## Factory Support for Testing

```ruby
# Create user with avatar in tests
user = create(:user, :with_avatar)

# Access avatar URL
user.avatar.url
```

## Security Features

- JWT authentication required for all avatar operations
- Users can only manage their own avatars
- File type validation (only images: jpg, jpeg, gif, png, webp)
- Unique secure filenames prevent collisions
- SSRF protection disabled in test environment only

## Migration to Production

Ready to deploy! The implementation:
- ✅ Uses your existing S3 credentials
- ✅ Follows your QR code upload pattern
- ✅ All tests passing (209 examples, 0 failures)
- ✅ Test fixtures created
- ✅ JWT authentication integrated
- ✅ Proper error handling
- ✅ JSON responses consistent with existing API

## Files Modified/Created

**Created:**
- `db/migrate/20251130172855_add_avatar_to_users.rb`
- `app/uploaders/avatar_uploader.rb`
- `app/controllers/api/v1/users_controller.rb`
- `app/views/api/v1/users/show.json.jbuilder`
- `spec/requests/api/v1/users_spec.rb`
- `spec/fixtures/files/test_avatar.jpg`
- `spec/fixtures/files/test_avatar2.jpg`

**Modified:**
- `app/models/user.rb` (added mount_uploader)
- `app/controllers/users/registrations_controller.rb` (permit avatar params)
- `app/views/users/registrations/create.json.jbuilder` (added avatar_url)
- `app/views/users/sessions/create.json.jbuilder` (added avatar_url)
- `app/views/current_user.json.jbuilder` (added avatar_url)
- `config/routes.rb` (added user resource routes)
- `spec/factories/users.rb` (added :with_avatar trait)

## Next Steps

1. **Deploy to production** - No additional configuration needed
2. **Update frontend** - Integrate avatar upload in user profile UI
3. **Use in brand pages** - Set `profileImage: user.avatar_url` in content JSON
4. **Optional enhancements**:
   - Add image resizing with MiniMagick/RMagick
   - Create thumbnail versions
   - Add file size validation
   - Implement direct S3 uploads for large files

## Test Results

```
209 examples, 0 failures, 16 pending
```

All avatar-related tests passing:
- ✅ Upload avatar during signup
- ✅ Get user profile with avatar
- ✅ Update avatar for authenticated user
- ✅ Replace existing avatar
- ✅ Remove avatar
- ✅ Proper authentication checks
- ✅ Error handling for missing files
