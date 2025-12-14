# Enhanced Analytics API Documentation

## Overview
The analytics system now provides comprehensive click and scan data with city-level geolocation and device type detection.

## API Endpoints

### 1. Get Link Analytics
**Endpoint:** `GET /api/v1/links/:lookup_code/analytics`

**Authentication:** Required (JWT token)

**Query Parameters:**
- `start_date` (optional): Start date for analytics range (default: 30 days ago)
  - Format: `YYYY-MM-DD`
  - Example: `2025-01-01`
- `end_date` (optional): End date for analytics range (default: today)
  - Format: `YYYY-MM-DD`
  - Example: `2025-01-31`

**Example Request:**
```bash
curl -X GET "https://thin.ly/api/v1/links/abc1234/analytics?start_date=2025-01-01&end_date=2025-01-31" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response Structure:**
```json
{
  "analytics": {
    "date_range": {
      "start_date": "2025-01-01",
      "end_date": "2025-01-31"
    },
    "summary": {
      "total_clicks": 1250,
      "human_clicks": 1180,
      "bot_clicks": 70,
      "qr_scans": 450,
      "direct_clicks": 730
    },
    "devices": {
      "mobile": 820,
      "desktop": 340,
      "tablet": 90
    },
    "top_cities": [
      {
        "city": "New York",
        "region": "NY",
        "country": "United States",
        "clicks": 245
      },
      {
        "city": "London",
        "region": "England",
        "country": "United Kingdom",
        "clicks": 189
      }
    ],
    "countries": [
      {
        "country": "United States",
        "clicks": 650
      },
      {
        "country": "United Kingdom",
        "clicks": 320
      }
    ],
    "browsers": [
      {
        "browser": "Chrome",
        "clicks": 720
      },
      {
        "browser": "Safari",
        "clicks": 380
      }
    ],
    "operating_systems": [
      {
        "os": "iOS",
        "clicks": 520
      },
      {
        "os": "Windows",
        "clicks": 410
      }
    ],
    "daily_clicks": [
      {
        "date": "2025-01-01",
        "clicks": 42
      },
      {
        "date": "2025-01-02",
        "clicks": 38
      }
    ],
    "recent_clicks": [
      {
        "id": 12345,
        "city": "San Francisco",
        "region": "CA",
        "country": "United States",
        "device_type": "mobile",
        "browser": "Chrome",
        "os": "iOS",
        "is_bot": false,
        "source": "qr",
        "created_at": "2025-01-15T14:32:00.000Z"
      }
    ]
  }
}
```

### 2. Get Link Details with Enhanced Clicks
**Endpoint:** `GET /api/v1/links/:lookup_code`

**Authentication:** Required (JWT token)

**Response:** The existing show endpoint now includes all enhanced analytics fields for each click:
```json
{
  "link": {
    "lookup_code": "abc1234",
    "original_url": "https://example.com",
    "title": "My Link",
    "clicks_count": 150,
    "clicks": [
      {
        "id": 12345,
        "country": "US",
        "ip_address": "1.2.3.4",
        "referrer": "https://twitter.com",
        "user_agent": "Mozilla/5.0...",
        "created_at": "2025-01-15T14:32:00.000Z",
        
        // Enhanced fields
        "city": "San Francisco",
        "region": "CA",
        "country_name": "United States",
        "postal_code": "94102",
        "latitude": 37.7749,
        "longitude": -122.4194,
        "timezone": "America/Los_Angeles",
        "device_type": "mobile",
        "browser": "Chrome",
        "browser_version": "120.0",
        "os": "iOS",
        "os_version": "17.2",
        "is_mobile": true,
        "is_tablet": false,
        "is_desktop": false,
        "is_bot": false,
        "source": "qr"
      }
    ]
  }
}
```

## Data Fields Explained

### Geolocation Fields
- `city`: City name (e.g., "San Francisco")
- `region`: State/province code (e.g., "CA")
- `country`: ISO country code (e.g., "US")
- `country_name`: Full country name (e.g., "United States")
- `postal_code`: ZIP/postal code
- `latitude`: Latitude coordinate (decimal, 6 digits precision)
- `longitude`: Longitude coordinate (decimal, 6 digits precision)
- `timezone`: IANA timezone (e.g., "America/Los_Angeles")

### Device Detection Fields
- `device_type`: Primary device category
  - Values: `"mobile"`, `"desktop"`, `"tablet"`, `"bot"`, `"smarttv"`, `"unknown"`
- `is_mobile`: Boolean flag for mobile devices
- `is_tablet`: Boolean flag for tablets
- `is_desktop`: Boolean flag for desktop computers
- `is_bot`: Boolean flag for bot/crawler traffic

### Browser & OS Fields
- `browser`: Browser name (Chrome, Safari, Firefox, Edge, Opera, Unknown)
- `browser_version`: Browser version number (e.g., "120.0")
- `os`: Operating system name (Windows, macOS, iOS, Android, Linux, Unknown)
- `os_version`: OS version (e.g., "10" for Windows 10, "17.2" for iOS 17.2)

### Traffic Source Fields
- `source`: Tracking source parameter
  - `"qr"`: Click came from QR code scan
  - `null`: Direct link click

## Model Scopes

The `Click` model includes helpful scopes for custom queries:

```ruby
# Device type scopes
Click.mobile      # All mobile clicks
Click.desktop     # All desktop clicks
Click.tablet      # All tablet clicks

# Traffic type scopes
Click.bots           # Bot/crawler traffic
Click.human_traffic  # Exclude bots
Click.qr_scans       # QR code scans only
Click.direct_clicks  # Direct link clicks only

# Location scopes
Click.by_country("United States")  # Filter by country name
Click.by_city("New York")          # Filter by city
Click.by_region("CA")              # Filter by state/region

# Time-based scopes
Click.today       # Today's clicks
Click.this_week   # This week's clicks
Click.this_month  # This month's clicks
Click.recent      # Last 100 clicks

# Example combined query
link.clicks.mobile.human_traffic.this_month.by_country("United States")
```

## Data Source

### With CloudFront (Recommended)
When CloudFront is configured with the proper origin request policy, geolocation and device detection headers are automatically extracted from CloudFront headers:
- No external API calls
- No rate limits
- Zero additional cost
- Real-time data

### Without CloudFront (Fallback)
When CloudFront headers are unavailable:
- User-Agent parsing provides browser, OS, and basic device detection
- Geolocation fields will be `null`
- Bot detection still works via User-Agent patterns

## CloudFront Setup (Required for Full Features)

To enable city-level geolocation and enhanced device detection:

1. Create CloudFront distribution with your Elastic Beanstalk environment as origin
2. Configure origin request policy to include these headers:
   - CloudFront-Viewer-Country
   - CloudFront-Viewer-Country-Name
   - CloudFront-Viewer-City
   - CloudFront-Viewer-Country-Region-Name
   - CloudFront-Viewer-Postal-Code
   - CloudFront-Viewer-Latitude
   - CloudFront-Viewer-Longitude
   - CloudFront-Viewer-Time-Zone
   - CloudFront-Is-Mobile-Viewer
   - CloudFront-Is-Tablet-Viewer
   - CloudFront-Is-Desktop-Viewer
   - CloudFront-Is-Android-Viewer
   - CloudFront-Is-IOS-Viewer
   - CloudFront-Is-SmartTV-Viewer
3. Update DNS to point to CloudFront distribution

## Rate Limits

✅ **No rate limits!** The system no longer uses external geolocation APIs like ipapi.co. All data comes from:
- CloudFront headers (native AWS, no limits)
- User-Agent parsing (local, no external calls)

## Performance Considerations

The analytics endpoint includes 8 database indexes for optimal query performance:
- Single column indexes: `city`, `region`, `country_name`, `device_type`, `is_mobile`, `is_bot`
- Composite indexes: `[link_id, created_at]`, `[device_type, created_at]`

Complex analytics queries with date ranges and grouping should perform well even with millions of clicks.
