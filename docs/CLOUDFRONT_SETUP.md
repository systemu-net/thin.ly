# CloudFront Setup Guide for Elastic Beanstalk

## Overview
This guide walks through setting up AWS CloudFront in front of your Elastic Beanstalk environment to enable city-level geolocation and device detection for analytics.

## Prerequisites
- AWS Console access
- Elastic Beanstalk environment running: `thin-ly-prod`
- Domain: `thin.ly` (and DNS management access)
- SSL certificate in ACM (AWS Certificate Manager)

## Step 1: Create CloudFront Distribution

### 1.1 Navigate to CloudFront
1. Open AWS Console
2. Go to **CloudFront** service
3. Click **Create Distribution**

### 1.2 Origin Settings
Configure the origin to point to your Elastic Beanstalk environment:

```
Origin domain: awseb-e8wbbaiehvbw-1468639567.us-east-1.elb.amazonaws.com
(Your ELB hostname)

Origin name: thin-ly-eb-origin

Protocol: HTTPS only (recommended) or Match viewer

Origin path: (leave empty)

Enable Origin Shield: No (optional for cost savings)
```

### 1.3 Default Cache Behavior Settings
Configure how CloudFront handles requests:

```
Path pattern: Default (*)

Viewer protocol policy: Redirect HTTP to HTTPS

Allowed HTTP methods: GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE

Cache policy: CachingDisabled (important for dynamic content)

Origin request policy: AllViewerAndCloudFrontHeaders-2022-06 (managed policy - REQUIRED!)
  This policy includes:
  - All viewer headers
  - All CloudFront geolocation headers (country, city, region, lat/long, timezone)
  - All CloudFront device detection headers (mobile, tablet, desktop, smartTV)

Response headers policy: None (or create custom if needed)
```

**CRITICAL**: You MUST use `AllViewerAndCloudFrontHeaders-2022-06` policy to get geolocation and device data!

### 1.4 Distribution Settings

```
Price class: Use all edge locations (best performance)
            OR Use only North America and Europe (cost savings)

Alternate domain names (CNAMEs): 
  - thin.ly
  - www.thin.ly

Custom SSL certificate: 
  - Select your ACM certificate for thin.ly
  - If you don't have one, request it first in ACM

Default root object: (leave empty for Rails routing)

Standard logging: Off (or configure S3 bucket if you want CloudFront logs)

IPv6: On

Description: thin.ly URL shortener with enhanced analytics
```

### 1.5 Review and Create
- Review all settings
- Click **Create distribution**
- Note the **Distribution domain name** (e.g., `d1234abcd5efgh.cloudfront.net`)
- Wait 5-15 minutes for deployment (Status: Enabled)

## Step 2: Create Custom Origin Request Policy

This is the **critical step** that enables geolocation and device detection headers.

### 2.1 Navigate to Origin Request Policies
1. In CloudFront console, go to **Policies** in left sidebar
2. Click **Origin request** tab
3. Click **Create origin request policy**

### 2.2 Policy Configuration

```
Name: thin-ly-geolocation-device-policy

Description: Forwards CloudFront geolocation and device detection headers to origin

Minimum TTL: 0 (for dynamic content)
```

### 2.3 Headers Configuration
**Select "Include the following headers"** and add these headers:

#### Geolocation Headers (8 headers):
```
CloudFront-Viewer-Country
CloudFront-Viewer-Country-Name
CloudFront-Viewer-City
CloudFront-Viewer-Country-Region-Name
CloudFront-Viewer-Postal-Code
CloudFront-Viewer-Latitude
CloudFront-Viewer-Longitude
CloudFront-Viewer-Time-Zone
```

#### Device Detection Headers (6 headers):
```
CloudFront-Is-Mobile-Viewer
CloudFront-Is-Tablet-Viewer
CloudFront-Is-Desktop-Viewer
CloudFront-Is-Android-Viewer
CloudFront-Is-IOS-Viewer
CloudFront-Is-SmartTV-Viewer
```

#### Essential Headers:
```
Host
User-Agent
CloudFront-Forwarded-Proto
```

**Total: 17 headers to forward**

### 2.4 Query Strings
```
Query strings: All
```

### 2.5 Cookies
```
Cookies: All
```

This ensures your Rails session and authentication cookies work correctly.

### 2.6 Create Policy
- Click **Create origin request policy**
- Go back to your distribution
- Edit the **Default cache behavior**
- Select your new **thin-ly-geolocation-device-policy** as the origin request policy
- Save changes

## Step 3: Update DNS Records

Update your DNS to point to CloudFront instead of directly to Elastic Beanstalk.

### 3.1 Get CloudFront Domain Name
From your distribution details, copy the **Distribution domain name**:
```
Example: d1234abcd5efgh.cloudfront.net
```

### 3.2 Update DNS Records
In your DNS provider (Route 53, Cloudflare, etc.):

**For Route 53:**
1. Go to **Route 53** → **Hosted zones** → `thin.ly`
2. Update/create these records:

```
Record 1 (root domain):
Name: thin.ly
Type: A (Alias)
Alias to: CloudFront distribution (select from dropdown)
Value: d1234abcd5efgh.cloudfront.net
Routing policy: Simple

Record 2 (www subdomain):
Name: www.thin.ly
Type: CNAME
Value: d1234abcd5efgh.cloudfront.net
TTL: 300
```

**For other DNS providers:**
```
Record 1:
Type: CNAME
Name: @ (or thin.ly)
Value: d1234abcd5efgh.cloudfront.net
TTL: 300

Record 2:
Type: CNAME
Name: www
Value: d1234abcd5efgh.cloudfront.net
TTL: 300
```

### 3.3 DNS Propagation
- DNS changes take 5-60 minutes to propagate
- Test with: `dig thin.ly` or `nslookup thin.ly`

## Step 4: Update Rails Host Authorization

Add CloudFront distribution to allowed hosts in production.

```ruby
# config/environments/production.rb

config.hosts << "d1234abcd5efgh.cloudfront.net"  # Your CloudFront domain
```

Or use a wildcard for CloudFront:
```ruby
config.hosts << /.*\.cloudfront\.net$/
```

Deploy the change:
```bash
git add config/environments/production.rb
git commit -m "Add CloudFront domain to allowed hosts"
git push origin develop
eb deploy thin-ly-prod
```

## Step 5: Test CloudFront Headers

### 5.1 Test via curl
```bash
# Test that CloudFront headers are being forwarded
curl -I https://thin.ly/api/v1/links

# Check response headers
curl -v https://thin.ly/yourlink 2>&1 | grep -i cloudfront
```

### 5.2 Test a Real Click
1. Create a test short link
2. Click it from your mobile phone
3. Check the database:

```bash
# SSH to your server
ssh -J ec2-user@98.90.191.32 ec2-user@10.0.103.39

# Check latest click
cd /var/app/current
bin/rails runner "
  click = Click.last
  puts 'Latest Click Analytics:'
  puts \"City: #{click.city}\"
  puts \"Country: #{click.country_name}\"
  puts \"Device Type: #{click.device_type}\"
  puts \"Browser: #{click.browser}\"
  puts \"Is Mobile: #{click.is_mobile}\"
"
```

### 5.3 Test Analytics API
```bash
# Get analytics for a link
curl -X GET "https://thin.ly/api/v1/links/abc1234/analytics" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" | jq .

# Check if cities and countries are populated
```

## Step 6: Monitor and Optimize

### 6.1 CloudFront Monitoring
- Go to CloudFront console → Your distribution → **Monitoring** tab
- Check:
  - Requests
  - Data transfer
  - Error rate
  - Cache hit ratio

### 6.2 Cost Monitoring
CloudFront costs are based on:
- Data transfer out (per GB)
- Number of requests
- Geographic region

**Typical costs for URL shortener:**
- First 10 TB/month: $0.085/GB (US)
- First 10M requests: $0.0075 per 10,000

### 6.3 Invalidations (if needed)
If you need to clear CloudFront cache:
```bash
aws cloudfront create-invalidation \
  --distribution-id E1234ABCD5EFGH \
  --paths "/*"
```

Note: First 1,000 invalidation paths per month are free.

## Troubleshooting

### Issue: Headers not being forwarded
**Solution:** Verify origin request policy includes all CloudFront headers

### Issue: SSL certificate errors
**Solution:** Ensure ACM certificate is in us-east-1 region (required for CloudFront)

### Issue: 502 Bad Gateway
**Solution:** 
- Check Elastic Beanstalk health
- Verify origin protocol settings
- Check security groups allow CloudFront IPs

### Issue: Geolocation still null in database
**Solution:**
1. Verify origin request policy is applied to default cache behavior
2. Check headers are being forwarded: `curl -v https://thin.ly`
3. Verify LinksController extract_cloudfront_headers method
4. Check ClickJob is receiving cloudfront_headers parameter

### Issue: CORS errors
**Solution:** Configure CORS in Rails to allow CloudFront domain

## Architecture Diagram

```
┌─────────────┐
│   User      │
└──────┬──────┘
       │
       │ HTTPS Request
       ▼
┌─────────────────────────────────────┐
│   CloudFront (Global Edge)          │
│   • Adds geolocation headers        │
│   • Adds device detection headers   │
│   • SSL termination                 │
│   • DDoS protection                 │
└──────────────┬──────────────────────┘
               │
               │ Forward with headers
               ▼
┌─────────────────────────────────────┐
│   Application Load Balancer (ELB)   │
│   us-east-1                         │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   Elastic Beanstalk                 │
│   • Rails API                       │
│   • Extracts CloudFront headers     │
│   • Logs click with analytics       │
└─────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   PostgreSQL RDS                    │
│   • Stores click analytics          │
│   • City-level geolocation          │
│   • Device type & browser data      │
└─────────────────────────────────────┘
```

## Benefits of CloudFront Setup

✅ **City-level geolocation** - No external API needed
✅ **Device detection** - Mobile, tablet, desktop, smartTV
✅ **Zero rate limits** - Native AWS feature
✅ **Zero additional cost** - Headers are free
✅ **Global performance** - Edge locations worldwide
✅ **DDoS protection** - AWS Shield Standard included
✅ **SSL/TLS** - Automatic HTTPS everywhere
✅ **Analytics** - CloudFront request logs

## Next Steps After Setup

1. ✅ Verify clicks have city/country data
2. ✅ Test analytics API endpoint
3. ✅ Monitor CloudFront costs (first month)
4. ✅ Update frontend to display city-level analytics
5. ✅ Create analytics dashboard using new API

## Reference Links

- [CloudFront Developer Guide](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/)
- [CloudFront Headers Reference](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html)
- [Elastic Beanstalk with CloudFront](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/environment-cfg-staticfiles.html)

---

**Setup Time:** ~30-45 minutes
**Cost Impact:** Minimal (~$5-20/month for typical traffic)
**Performance Impact:** Improved (CDN caching + global edge locations)
