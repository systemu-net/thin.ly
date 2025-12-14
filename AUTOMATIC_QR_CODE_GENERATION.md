# Automatic QR Code Generation for Links

## Overview
Implemented automatic QR code generation for every link created in the thin.ly URL shortener. When a user creates a new link, a QR code is automatically generated in the background using Sidekiq.

## Implementation Details

### 1. QrCodeGeneratorJob (Sidekiq Worker)
**File**: `app/jobs/qr_code_generator_job.rb`

- Background job that generates QR codes for links
- Checks if QR code already exists to prevent duplicates
- Uses the existing `QrGenerator` service
- **Logs API requests** to track QR code usage against plan limits
- Includes error handling and logging

**Key Features**:
- ✅ Asynchronous processing (doesn't slow down link creation)
- ✅ Duplicate prevention (one QR code per user per link)
- ✅ **API request tracking** (counts toward QR code plan limits)
- ✅ Error handling with logging
- ✅ Graceful handling of missing links

### 2. Links Controller Update
**File**: `app/controllers/api/v1/links_controller.rb`

Added `generate_qr_code` method that enqueues the QR code generation job:

```ruby
def generate_qr_code(link)
  QrCodeGeneratorJob.perform_async(link.id)
end
```

This method is called in the `create` action immediately after a link is created.

### 3. QrCodeUploader Fix
**File**: `app/uploaders/qr_code_uploader.rb`

- Removed hardcoded `storage :fog` 
- Now respects global CarrierWave configuration
- Uses file storage in test environment
- Uses S3 (fog) in production/development

### 4. Factory Update
**File**: `spec/factories/qr_codes.rb`

- Added default image for QR code factory
- Enables testing without S3 interaction

### 5. Comprehensive Tests
**File**: `spec/jobs/qr_code_generator_job_spec.rb`

- Tests QR code generation for new links
- Tests duplicate prevention
- **Tests API request logging**
- Tests error handling for missing links
- All 8 tests passing ✅

## User Experience Flow

### Before:
1. User creates link
2. User manually creates QR code (separate API call)
3. Two steps, manual process

### After:
1. User creates link
2. QR code automatically generated in background
3. One step, automatic process ✅

## API Behavior

### Create Link Endpoint: `POST /api/v1/links`

**Request**:
```json
{
  "link": {
    "original_url": "https://example.com/my-long-url"
  }
}
```

**Response** (immediate):
```json
{
  "link": {
    "lookup_code": "abc1234",
    "original_url": "https://example.com/my-long-url",
    "shortened_url": "http://thin.ly/abc1234",
    "clicks_count": 0,
    "qr_codes": []  // Empty initially
  }
}
```

**Background Processing**:
- Within seconds, QR code is generated and stored in S3
- **API request is logged** to track usage against plan limits
- Next API call will include the QR code

**Subsequent GET request** returns:
```json
{
  "link": {
    "lookup_code": "abc1234",
    "qr_codes": [
      {
        "id": 123,
        "image": "https://thinly.s3.amazonaws.com/uploads/qr_code/abc1234.png"
      }
    ]
  }
}
```

## Benefits

### For Users:
1. **Automatic**: No need to remember to create QR codes
2. **Fast**: Link creation isn't slowed down by QR generation
3. **Convenient**: Every link comes with a QR code
4. **Free tier friendly**: Uses the same API request tracking

### For Business:
1. **Better UX**: One-click link creation with QR code
2. **Competitive advantage**: Matches/exceeds competitors (Bitly, Short.io)
3. **Increased value**: More features in free tier
4. **Lower support**: Fewer "how do I create QR code?" questions

### Technical:
1. **Scalable**: Sidekiq handles background processing
2. **Reliable**: Jobs are retried on failure
3. **Efficient**: Doesn't block API responses
4. **Maintainable**: Clean separation of concerns

## Monitoring & Debugging

### Check Sidekiq Queue:
```bash
bundle exec sidekiq
```

### Check Job Status in Rails Console:
```ruby
# Find link
link = Link.find_by(lookup_code: 'abc1234')

# Check if QR code exists
link.qr_codes.any?

# View QR code URL
link.qr_codes.first&.image&.url

# Check API request logs for QR codes
user = link.user
user.plan.api_requests.where(logable_type: 'QrCode').count
user.plan.qr_codes_created_within_last_30_days
```

### Manual QR Code Generation (if needed):
```ruby
link = Link.find(123)
QrCodeGeneratorJob.new.perform(link.id)
```

## Future Enhancements

### Short-term:
- [ ] Add QR code customization (colors, logo overlay)
- [x] **QR code scan tracking** - Track QR scans separately from direct clicks
- [ ] Allow multiple QR codes per link with different styles

### Long-term:
- [ ] Dynamic QR codes (update destination without changing QR)
- [ ] QR code templates for different use cases
- [ ] Bulk QR code generation for existing links

## QR Code Scan Tracking

**Implemented**: December 5, 2025

Each QR code now includes a `?r=qr` tracking parameter, allowing differentiation between QR code scans and direct link clicks.

### Features:
- ✅ `scans_count` field in QR codes API responses
- ✅ Tracks clicks with `source: 'qr'` in the clicks table
- ✅ Indexed `source` column for fast queries
- ✅ Available in all QR code endpoints (index, show, create)

### API Response Example:
```json
{
  "qr_codes": [
    {
      "id": 123,
      "image_url": "/uploads/qr_code/example.png",
      "created_at": "2025-12-05T22:00:00.000Z",
      "updated_at": "2025-12-05T22:00:00.000Z",
      "link": {
        "lookup_code": "abc1234",
        "original_url": "https://example.com",
        "title": "Example Link",
        "description": "An example",
        "scans_count": 42
      }
    }
  ]
}
```

### Analytics Queries:
```ruby
# Get QR scans for a specific QR code
qr_code.scans_count  # => 42

# Get QR scans for a link
link.clicks.where(source: 'qr').count  # => 42

# QR scan rate
qr_scans = link.clicks.where(source: 'qr').count
total_clicks = link.clicks_count
scan_rate = (qr_scans.to_f / total_clicks * 100).round(2)  # => 35.7%

# All clicks grouped by source
link.clicks.group(:source).count
# => {"qr" => 42, nil => 76}
```

### Database Schema:
- Added `source` column to `clicks` table (string, indexed)
- Migration: `20251205223658_add_source_to_clicks.rb`

## Testing

All tests pass:
- ✅ QR code generator job tests (8 examples)
- ✅ Links controller tests (26 examples)
- ✅ QR code model tests with scans_count (5 examples)
- ✅ QR codes API tests with scans_count (4 examples)
- ✅ Integration with existing test suite (225 total examples, 0 failures)

Run tests:
```bash
bundle exec rspec spec/jobs/qr_code_generator_job_spec.rb
bundle exec rspec spec/requests/links_spec.rb
bundle exec rspec spec/models/qr_code_spec.rb
bundle exec rspec spec/requests/api/v1/qr_codes_spec.rb
```

## Rollout Notes

### Production Deployment:
1. Deploy code changes
2. Restart Sidekiq workers
3. Monitor Sidekiq queues for any issues
4. Check S3 bucket for QR code uploads

### Backfill Existing Links (Optional):
If you want to generate QR codes for existing links without QR codes:

```ruby
# In Rails console
Link.includes(:qr_codes).find_each do |link|
  next if link.qr_codes.exists?(user_id: link.user_id)
  QrCodeGeneratorJob.perform_async(link.id)
end
```

## Pricing Impact

✅ **No impact on pricing tiers** - QR code generation uses existing infrastructure:
- Free tier: 50 links/month → 50 QR codes/month (automatic)
- Creator: Unlimited links → Unlimited QR codes
- Business+: Same benefits continue

## Conclusion

This implementation aligns perfectly with the competitive analysis you provided:
- ✅ Matches Bitly's automatic QR code generation
- ✅ Better UX than requiring manual QR creation
- ✅ Positions thin.ly as a comprehensive link management solution
- ✅ Adds value without increasing complexity

The feature is production-ready and fully tested! 🎉
