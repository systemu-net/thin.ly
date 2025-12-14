# Avatar Integration Example for Brand Pages

## Frontend Integration Example

### 1. Upload Avatar on User Profile Page

```javascript
// Upload avatar for logged-in user
async function uploadAvatar(file) {
  const formData = new FormData();
  formData.append('avatar', file);

  const response = await fetch('/api/v1/user/avatar', {
    method: 'PATCH',
    headers: {
      'Authorization': `Bearer ${authToken}`
    },
    body: formData
  });

  const data = await response.json();
  console.log('Avatar uploaded:', data.avatar_url);
  return data.avatar_url;
}

// Usage in file input handler
document.getElementById('avatar-upload').addEventListener('change', async (e) => {
  const file = e.target.files[0];
  if (file) {
    const avatarUrl = await uploadAvatar(file);
    // Update UI with new avatar
    document.getElementById('profile-image').src = avatarUrl;
  }
});
```

### 2. Get Current User with Avatar

```javascript
async function getCurrentUser() {
  const response = await fetch('/api/v1/current_user', {
    headers: {
      'Authorization': `Bearer ${authToken}`
    }
  });

  const data = await response.json();
  return data.user; // Response has nested user object
}

// Usage
const user = await getCurrentUser();
console.log('User avatar:', user.avatar_url);
console.log('User plan:', user.plan.name);
console.log('User role:', user.role);
```

### 3. Auto-populate Brand Page with User Avatar

```javascript
async function createBrandPageWithUserAvatar() {
  // Get current user
  const user = await getCurrentUser();

  // Create brand page with user's avatar as profileImage
  const brandPageData = {
    brand_page: {
      title: "My Personal Page",
      description: "Welcome to my page",
      content: {
        button: "rounded",
        social: {
          linkedin: "https://www.linkedin.com/in/...",
          fb: "https://www.facebook.com/..."
        },
        textColor: "#ffffff",
        fontFamily: "rubik",
        buttonColor: "#ffffff",
        gradientEnd: "#0000ff",
        profileImage: user.avatar_url, // ← Auto-use user's avatar
        gradientStart: "#ff00ff",
        backgroundType: "gradient",
        gradientDirection: "to bottom left"
      }
    }
  };

  const response = await fetch('/api/v1/brand_pages', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${authToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(brandPageData)
  });

  return await response.json();
}
```

### 4. React Component Example

```jsx
import React, { useState, useEffect } from 'react';

function UserProfile({ authToken }) {
  const [user, setUser] = useState(null);
  const [uploading, setUploading] = useState(false);

  // Load user data on mount
  useEffect(() => {
    fetchUser();
  }, []);

  async function fetchUser() {
    const response = await fetch('http://localhost:3000/api/v1/current_user', {
      headers: { 'Authorization': `Bearer ${authToken}` }
    });
    const data = await response.json();
    setUser(data.user); // Extract user from nested response
  }

  async function handleAvatarUpload(event) {
    const file = event.target.files[0];
    if (!file) return;

    setUploading(true);
    const formData = new FormData();
    formData.append('avatar', file);

    try {
      const response = await fetch('/api/v1/user/avatar', {
        method: 'PATCH',
        headers: { 'Authorization': `Bearer ${authToken}` },
        body: formData
      });

      const data = await response.json();
      
      // Update user state with new avatar URL
      setUser(prev => ({ ...prev, avatar_url: data.avatar_url }));
    } catch (error) {
      console.error('Avatar upload failed:', error);
    } finally {
      setUploading(false);
    }
  }

  async function handleAvatarRemove() {
    try {
      await fetch('/api/v1/user/avatar', {
        method: 'DELETE',
        headers: { 'Authorization': `Bearer ${authToken}` }
      });

      // Remove avatar from state
      setUser(prev => ({ ...prev, avatar_url: null }));
    } catch (error) {
      console.error('Avatar removal failed:', error);
    }
  }

  if (!user) return <div>Loading...</div>;

  return (
    <div className="user-profile">
      <div className="avatar-section">
        {user.avatar_url ? (
          <img 
            src={user.avatar_url} 
            alt="User avatar" 
            className="avatar-image"
          />
        ) : (
          <div className="avatar-placeholder">No Avatar</div>
        )}
        
        <div className="avatar-actions">
          <label className="upload-button">
            {uploading ? 'Uploading...' : 'Upload Avatar'}
            <input 
              type="file" 
              accept="image/*" 
              onChange={handleAvatarUpload}
              disabled={uploading}
              style={{ display: 'none' }}
            />
          </label>
          
          {user.avatar_url && (
            <button onClick={handleAvatarRemove}>Remove Avatar</button>
          )}
        </div>
      </div>

      <div className="user-info">
        <h2>{user.email}</h2>
        <p>User ID: {user.id}</p>
      </div>
    </div>
  );
}

export default UserProfile;
```

### 5. Complete ReactJS Hook for Current User with Avatar

```jsx
import { useState, useEffect } from 'react';

// Custom hook for managing current user
function useCurrentUser(authToken) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!authToken) {
      setLoading(false);
      return;
    }

    fetchCurrentUser();
  }, [authToken]);

  async function fetchCurrentUser() {
    try {
      setLoading(true);
      const response = await fetch('http://localhost:3000/api/v1/current_user', {
        headers: {
          'Authorization': `Bearer ${authToken}`,
          'Content-Type': 'application/json'
        }
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      
      // Response structure:
      // {
      //   "user": {
      //     "id": 19,
      //     "email": "test123@example.com",
      //     "avatar_url": "http://thinly.s3.amazonaws.com/...",
      //     "role": "admin",
      //     "plan": { "name": "Free", "features": [...] },
      //     "created_at": "2025-11-30T18:24:10.013Z",
      //     "updated_at": "2025-11-30T18:30:01.891Z",
      //     "jti": "96277588-df7d-4e9e-90cd-37428f15513d"
      //   }
      // }
      
      setUser(data.user);
      setError(null);
    } catch (err) {
      setError(err.message);
      setUser(null);
    } finally {
      setLoading(false);
    }
  }

  return { user, loading, error, refetch: fetchCurrentUser };
}

// Usage in component
function MyComponent() {
  const authToken = localStorage.getItem('authToken');
  const { user, loading, error, refetch } = useCurrentUser(authToken);

  if (loading) return <div>Loading...</div>;
  if (error) return <div>Error: {error}</div>;
  if (!user) return <div>Please log in</div>;

  return (
    <div>
      <img src={user.avatar_url || '/default-avatar.png'} alt="Avatar" />
      <h1>{user.email}</h1>
      <p>Role: {user.role}</p>
      <p>Plan: {user.plan.name}</p>
      <div>
        <h3>Plan Features:</h3>
        {user.plan.features.map(feature => (
          <div key={feature.name}>
            {feature.name}: {feature.used}/{feature.limit}
          </div>
        ))}
      </div>
    </div>
  );
}
```

### 6. Brand Page Editor - Auto-suggest User Avatar

```jsx
function BrandPageEditor({ authToken, brandPage, onUpdate }) {
  const [user, setUser] = useState(null);

  useEffect(() => {
    // Fetch user on mount
    fetch('http://localhost:3000/api/v1/current_user', {
      headers: { 'Authorization': `Bearer ${authToken}` }
    })
      .then(res => res.json())
      .then(data => setUser(data.user)); // Extract user from nested response
  }, []);

  function useMyAvatar() {
    if (!user?.avatar_url) {
      alert('Please upload an avatar first');
      return;
    }

    // Update brand page with user's avatar
    onUpdate({
      ...brandPage,
      content: {
        ...brandPage.content,
        profileImage: user.avatar_url
      }
    });
  }

  return (
    <div className="brand-page-editor">
      <div className="profile-image-section">
        <label>Profile Image URL</label>
        <input 
          type="text"
          value={brandPage.content.profileImage || ''}
          onChange={(e) => onUpdate({
            ...brandPage,
            content: {
              ...brandPage.content,
              profileImage: e.target.value
            }
          })}
        />
        
        {user?.avatar_url && (
          <button onClick={useMyAvatar} className="use-avatar-btn">
            Use My Avatar
          </button>
        )}
      </div>
      
      {/* Preview */}
      {brandPage.content.profileImage && (
        <div className="preview">
          <img 
            src={brandPage.content.profileImage} 
            alt="Profile preview"
            className="preview-image"
          />
        </div>
      )}
    </div>
  );
}
```

## Backend Integration (Rails Controllers)

### Using Avatar in API Responses

```ruby
# In any controller that returns user data
def show_with_avatar
  user = User.find(params[:id])
  
  render json: {
    id: user.id,
    email: user.email,
    avatar_url: user.avatar.url, # Returns S3 URL or nil
    # ... other user fields
  }
end
```

### Automatically Use User Avatar in New Brand Pages

```ruby
# In BrandPagesController
def create
  @brand_page = current_user.brand_pages.new(brand_page_params)
  
  # Auto-populate profileImage with user's avatar if not provided
  if @brand_page.content['profileImage'].blank? && current_user.avatar.present?
    @brand_page.content['profileImage'] = current_user.avatar.url
  end
  
  if @brand_page.save
    render :show, status: :created
  else
    render json: { errors: @brand_page.errors.full_messages }, 
           status: :unprocessable_entity
  end
end
```

## cURL Examples

### Upload Avatar
```bash
curl -X PATCH "http://localhost:3000/api/v1/user/avatar" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -F "avatar=@/path/to/photo.jpg"
```

### Get Current User with Avatar
```bash
curl -X GET "http://localhost:3000/api/v1/current_user" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"

# Example Response:
# {
#   "user": {
#     "id": 19,
#     "email": "test123@example.com",
#     "avatar_url": "http://thinly.s3.amazonaws.com/uploads/user/avatar/19/avatar_035228ed-c145-4c39-95aa-29bb684bc6c6.jpg",
#     "role": "admin",
#     "plan": {
#       "name": "Free",
#       "features": [
#         {"name": "links", "limit": 50, "used": 0},
#         {"name": "qr_codes", "limit": 5, "used": 0},
#         {"name": "brand_pages", "limit": 1, "used": 0}
#       ]
#     },
#     "created_at": "2025-11-30T18:24:10.013Z",
#     "updated_at": "2025-11-30T18:30:01.891Z",
#     "jti": "96277588-df7d-4e9e-90cd-37428f15513d"
#   }
# }
```

### Create Brand Page with Avatar
```bash
curl -X POST "http://localhost:3000/api/v1/brand_pages" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "brand_page": {
      "title": "My Page",
      "content": {
        "profileImage": "https://your-bucket.s3.amazonaws.com/uploads/user/avatar/1/avatar_xyz.jpg",
        "button": "rounded",
        "textColor": "#fff",
        "fontFamily": "rubik"
      }
    }
  }'
```

## Security Notes

1. **Authentication Required**: All avatar operations require valid JWT token
2. **File Type Validation**: Only image files (jpg, jpeg, gif, png, webp) are accepted
3. **User Isolation**: Users can only access/modify their own avatars
4. **S3 Security**: Files stored in private S3 bucket with signed URLs

## Performance Considerations

1. **CDN**: Consider using CloudFront CDN in front of S3 for faster delivery
2. **Image Optimization**: Add MiniMagick/RMagick for automatic resizing
3. **Caching**: Avatar URLs are stable; cache them in frontend
4. **Direct Upload**: For large files, implement direct S3 upload to reduce server load

## Common Issues & Solutions

### Issue: "No avatar file provided"
**Solution**: Ensure you're using `multipart/form-data` content type

### Issue: Avatar not showing after upload
**Solution**: Check CORS settings on S3 bucket

### Issue: Avatar URL is null in response
**Solution**: User hasn't uploaded avatar yet; provide default image in frontend

### Issue: "ArgumentError: is not a recognized provider"
**Solution**: Check AWS credentials in `config/initializers/carrierwave.rb`
