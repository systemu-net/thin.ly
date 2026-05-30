# Blog images — current placeholders + AI generation prompts

Every image in the blog is currently a stable Picsum URL (real
photographer photos, seeded so they don't rotate). They're good
enough to ship — the posts look populated immediately on first build.

This file is the swap manifest for replacing them with AI-generated
images that actually match the content. For each image:

- The **path** is where the post references it. Search and replace
  the `<img src>` value in the post once you have the file.
- The **target local path** is where to drop the generated PNG/JPG.
  Use `/assets/images/...` as the new `src` (relative to the blog
  baseurl `/blog/`).
- The **prompt** is what to send to your image generator.

## Style guide for AI generation

Use this as a system prefix on every prompt so the images stay
visually consistent across the blog:

> Editorial illustration in a clean, modern, slightly muted style.
> Soft natural lighting. Generous negative space. Brand accent color
> is violet (#6d28d9 / #7c3aed). Avoid clichéd stock-photography
> tropes — no high-fives, no people pointing at laptops, no
> blueprint hands. Avoid heavy text overlays; if any text is shown
> in the image, keep it short and legible. 16:9 aspect ratio,
> photorealistic or 3D render quality, not flat vector art.

## Aspect ratios

- **Hero**: 1600 × 900 (16:9)
- **Inline**: 1200 × 675 (16:9)

When generating, prefer the larger size and let your CMS resize down.

---

## Post 1 — UTM Parameters

### Hero

- **Current**: `https://picsum.photos/seed/thinly-utm-hero/1600/900`
- **Target**: `/assets/images/utm-parameters/hero.jpg`
- **Prompt**: A clean, editorial overhead shot of a desktop workspace
  with a large laptop screen showing a colorful analytics dashboard.
  Multiple campaign cards visible with click counts and percentage
  changes. Coffee cup, notebook, and a smartphone with a similar
  dashboard view nearby. Muted natural light from a window on the
  left. Violet accents in the dashboard visuals.

### Inline 1 — UTM stack diagram

- **Current**: `https://picsum.photos/seed/thinly-utm-stack/1200/675`
- **Target**: `/assets/images/utm-parameters/utm-stack.jpg`
- **Prompt**: A clean 3D-rendered diagram showing layered translucent
  cards: top card labeled "Short link wrapper" with a thin.ly-style
  URL, second card "Destination URL" with a longer path, third card
  "UTM parameters" with key/value chips. The cards are stacked with
  visible depth, soft purple gradient background.

### Inline 2 — UTM vocabulary

- **Current**: `https://picsum.photos/seed/thinly-utm-vocabulary/1200/675`
- **Target**: `/assets/images/utm-parameters/vocabulary.jpg`
- **Prompt**: Close-up of a whiteboard or notebook page with a
  hand-written marketing UTM convention list — utm_source values
  (linkedin, newsletter, partner), utm_medium values (cpc, email,
  social). Pen resting on the notebook. Soft daylight from one side.
  Subtle violet highlighter marks on key terms.

### Inline 3 — UTM workflow

- **Current**: `https://picsum.photos/seed/thinly-utm-workflow/1200/675`
- **Target**: `/assets/images/utm-parameters/workflow.jpg`
- **Prompt**: A clean, modern process diagram with four numbered
  steps connected by arrows: 1) Campaign brief, 2) Tagged
  destination URL, 3) Shortened link, 4) Attributed click in
  analytics. Each step shown as an icon-and-label card. Violet
  accent color on the arrows. Light grey background. Minimalist.

---

## Post 2 — QR Codes for Print

### Hero

- **Current**: `https://picsum.photos/seed/thinly-qr-hero/1600/900`
- **Target**: `/assets/images/qr-codes-for-print/hero.jpg`
- **Prompt**: Photorealistic close-up of a printed event poster on a
  wall, with a large QR code prominently in the lower right and a
  short URL printed clearly underneath. A hand is holding a
  smartphone framing the QR code, mid-scan. Warm gallery lighting.
  Shallow depth of field with the QR code in sharp focus.

### Inline 1 — Dynamic vs static comparison

- **Current**: `https://picsum.photos/seed/thinly-qr-dynamic/1200/675`
- **Target**: `/assets/images/qr-codes-for-print/dynamic-vs-static.jpg`
- **Prompt**: Side-by-side comparison illustration: left half labeled
  "STATIC" showing a printed QR code with a broken/error icon on the
  destination screen; right half labeled "DYNAMIC" showing the same
  printed QR code but the destination screen has been updated to a
  new campaign. Subtle violet accent labels. Clean editorial design.

### Inline 2 — Sizing on a poster

- **Current**: `https://picsum.photos/seed/thinly-qr-poster/1200/675`
- **Target**: `/assets/images/qr-codes-for-print/sizing.jpg`
- **Prompt**: A hotel lobby with a large vertical advertising poster
  on a stand, a large QR code prominently displayed at viewing
  height, a person standing across the room (about 3 meters away)
  holding up their phone to scan. The scale relationship between
  viewer distance and QR code size is clear.

### Inline 3 — Code in context with text

- **Current**: `https://picsum.photos/seed/thinly-qr-context/1200/675`
- **Target**: `/assets/images/qr-codes-for-print/context.jpg`
- **Prompt**: A printed restaurant table card or menu showing a QR
  code with clear, friendly text above it ("Scan to see the wine
  list"). Warm restaurant lighting, slight depth of field, the
  card framed by a partial place setting. Editorial food-magazine
  style.

---

## Post 3 — Understanding Link Analytics

### Hero

- **Current**: `https://picsum.photos/seed/thinly-analytics-hero/1600/900`
- **Target**: `/assets/images/link-analytics/hero.jpg`
- **Prompt**: A wide editorial shot of a modern analytics dashboard
  on a large monitor: a line chart of clicks over time, a small
  world map with country click densities, a device-split donut
  chart, and a referrer table. Violet brand accent on key metrics.
  Slightly off-axis composition with a coffee mug and notebook in
  the foreground, suggesting a marketer reviewing data.

### Inline 1 — Total vs unique clicks

- **Current**: `https://picsum.photos/seed/thinly-analytics-uniques/1200/675`
- **Target**: `/assets/images/link-analytics/uniques.jpg`
- **Prompt**: A side-by-side comparison of two line charts on a
  clean dashboard interface: one labeled "Total clicks" (higher
  line), one labeled "Unique clicks" (lower line, parallel). The
  gap between them is shaded subtly. Violet accent on the unique
  line. Minimalist, editorial.

### Inline 2 — Geographic heatmap

- **Current**: `https://picsum.photos/seed/thinly-analytics-geo/1200/675`
- **Target**: `/assets/images/link-analytics/geo.jpg`
- **Prompt**: A world map shown as a clean choropleth heatmap with
  click densities indicated by color intensity (light cream to
  deep violet). Sparse country labels for the highest-density
  regions. Subtle grid background. Dashboard-card style framing.

### Inline 3 — Hourly distribution

- **Current**: `https://picsum.photos/seed/thinly-analytics-hourly/1200/675`
- **Target**: `/assets/images/link-analytics/hourly.jpg`
- **Prompt**: A 24-hour bar histogram showing click distribution by
  hour of day, with a clear working-hours peak (9am-6pm) and a small
  late-evening secondary peak. Violet bars on a soft grey
  background. Hour labels on x-axis, "Clicks" label on y-axis.
  Clean dashboard chart aesthetic.

---

## Post 4 — URL Shortener Security

### Hero

- **Current**: `https://picsum.photos/seed/thinly-security-hero/1600/900`
- **Target**: `/assets/images/url-shortener-security/hero.jpg`
- **Prompt**: A photorealistic abstract concept of digital trust: a
  glowing padlock icon floating above a network of soft-glowing
  connection lines representing URL redirects. Deep dark navy
  background with violet and cyan accent glows. Cinematic
  lighting. Not clipart — render in a modern 3D-art style.

### Inline 1 — Four threat categories

- **Current**: `https://picsum.photos/seed/thinly-security-threats/1200/675`
- **Target**: `/assets/images/url-shortener-security/threats.jpg`
- **Prompt**: A clean grid of four threat-icon cards labeled:
  "Malware", "Phishing", "Scams", "Policy violations". Each card
  has a minimalist warning icon and a soft red/orange accent.
  Editorial diagram style on a light background.

### Inline 2 — Multi-layer scanning

- **Current**: `https://picsum.photos/seed/thinly-security-scanning/1200/675`
- **Target**: `/assets/images/url-shortener-security/scanning.jpg`
- **Prompt**: An abstract diagram showing a URL passing through
  several layered "scanner" panels — labeled with names like Safe
  Browsing, Heuristic check, Sandboxed inspection. Each panel adds
  a check mark or annotation as the URL passes through. Modern
  glassmorphism style with violet gradient accents.

### Inline 3 — Safety interstitial

- **Current**: `https://picsum.photos/seed/thinly-security-interstitial/1200/675`
- **Target**: `/assets/images/url-shortener-security/interstitial.jpg`
- **Prompt**: A laptop screen displaying a clean, friendly safety
  warning page: a shield icon, headline "This link was flagged as
  unsafe", explanatory body text, and a "Report a false positive"
  button. The browser address bar shows a thin.ly short URL. Soft
  natural lighting. Photographed from a slight angle.

---

## Post 5 — Branded vs Generic Shorteners

### Hero

- **Current**: `https://picsum.photos/seed/thinly-branded-hero/1600/900`
- **Target**: `/assets/images/branded-vs-generic/hero.jpg`
- **Prompt**: A large outdoor billboard in a city at golden hour,
  displaying a campaign with a branded short URL (e.g.
  "acme.link/launch") prominently centered. The billboard's brand
  identity is clear. Wide cinematic shot looking up at the
  billboard. Warm light, deep shadows. Photorealistic.

### Inline 1 — Branded vs generic link preview

- **Current**: `https://picsum.photos/seed/thinly-branded-trust/1200/675`
- **Target**: `/assets/images/branded-vs-generic/trust.jpg`
- **Prompt**: A smartphone screen split-screen showing two link
  previews side by side: left one shows a generic-shortener URL
  ("thin.ly/abc1234"), right one shows a branded URL
  ("acme.link/launch"). A subtle "more trusted" annotation on the
  branded side. Clean modern UI. Editorial product-photography
  style.

### Inline 2 — Cost breakdown

- **Current**: `https://picsum.photos/seed/thinly-branded-cost/1200/675`
- **Target**: `/assets/images/branded-vs-generic/cost.jpg`
- **Prompt**: A clean horizontal bar-chart illustration showing
  cost categories for branded domain setup: "Domain registration",
  "Plan tier", "DNS/SSL", "Internal coordination". Bars in
  graduated violet shades. Soft grey background. Dashboard-style.

### Inline 3 — Subdomain configuration

- **Current**: `https://picsum.photos/seed/thinly-branded-subdomain/1200/675`
- **Target**: `/assets/images/branded-vs-generic/subdomain.jpg`
- **Prompt**: A clean UI mockup of a "Custom domain" configuration
  panel inside a modern SaaS product: input field showing
  "acme.thin.ly", a status badge "Verified ✓ SSL active", and a
  "Save" button in violet. Soft drop shadows. Light theme.

---

## Post 6 — Link Governance

### Hero

- **Current**: `https://picsum.photos/seed/thinly-governance-hero/1600/900`
- **Target**: `/assets/images/link-governance/hero.jpg`
- **Prompt**: A wide editorial shot of a modern audit-log interface
  on a monitor: timeline view with state-change entries (paused,
  resumed, destination changed, expired), each entry tagged with a
  user avatar and timestamp. Violet accent on the most recent
  entry. Slightly off-axis composition with a desk plant and
  coffee mug in the soft foreground.

### Inline 1 — Pause action

- **Current**: `https://picsum.photos/seed/thinly-governance-pause/1200/675`
- **Target**: `/assets/images/link-governance/pause.jpg`
- **Prompt**: A close-up UI mockup of a link's dashboard row with a
  clearly visible "Paused" status badge in soft amber and a "Resume"
  button highlighted in violet. The click-count number is preserved
  next to the status. Modern, clean SaaS aesthetic.

### Inline 2 — Routing rules

- **Current**: `https://picsum.photos/seed/thinly-governance-routing/1200/675`
- **Target**: `/assets/images/link-governance/routing.jpg`
- **Prompt**: A flow diagram showing a single short link branching
  into three destinations based on conditions: "If country = EU
  → eu-landing", "If device = mobile → app-store-deep-link",
  "Default → main-landing". Clean diagram with violet condition
  branches. Light theme.

### Inline 3 — Audit log timeline

- **Current**: `https://picsum.photos/seed/thinly-governance-audit/1200/675`
- **Target**: `/assets/images/link-governance/audit.jpg`
- **Prompt**: A vertical timeline UI showing successive link events:
  "Created by Sarah · Mar 4", "Destination updated by Tomás · Apr
  12", "Paused by Sarah · May 1", "Resumed by Tomás · May 18",
  each with a small avatar and timestamp. Clean modern interface
  on a light background.

---

## Post 7 — Custom Domains

### Hero

- **Current**: `https://picsum.photos/seed/thinly-domains-hero/1600/900`
- **Target**: `/assets/images/custom-domains/hero.jpg`
- **Prompt**: A close-up of a DNS zone editor on a developer's
  monitor: rows of records (A, CNAME, TXT) with editable fields.
  One CNAME record is highlighted in violet, mid-edit. Slight
  bokeh in the background suggesting a development environment.
  Modern editor aesthetic.

### Inline 1 — Picking the domain

- **Current**: `https://picsum.photos/seed/thinly-domains-picking/1200/675`
- **Target**: `/assets/images/custom-domains/picking.jpg`
- **Prompt**: A clean grid of candidate short-domain options across
  multiple TLDs: "acme.link", "acme.co", "acme.io", "go.acme.com",
  each with a small "available" or "taken" indicator. Modern
  domain-search UI mockup. Violet accents on available results.

### Inline 2 — DNS records

- **Current**: `https://picsum.photos/seed/thinly-domains-dns/1200/675`
- **Target**: `/assets/images/custom-domains/dns.jpg`
- **Prompt**: A clean table-style UI showing DNS records for a
  short domain: CNAME record pointing to `custom.thin.ly`, two A
  records, a TXT verification record. Each row has a small status
  indicator. Modern admin-panel aesthetic on a light background.
  Violet accents.

### Inline 3 — Valid SSL certificate

- **Current**: `https://picsum.photos/seed/thinly-domains-ssl/1200/675`
- **Target**: `/assets/images/custom-domains/ssl.jpg`
- **Prompt**: A close-up of a browser's address bar showing
  `https://acme.link/launch` with a green padlock icon and a valid
  certificate tooltip showing "Connection is secure · Issued by
  Let's Encrypt". Clean modern browser UI. Soft natural lighting
  on the laptop screen.

---

## Post 8 — QR Code vs Short Link

### Hero

- **Current**: `https://picsum.photos/seed/thinly-vs-hero/1600/900`
- **Target**: `/assets/images/qr-vs-link/hero.jpg`
- **Prompt**: Photorealistic close-up of a printed marketing card or
  poster showing a QR code in the upper half and a printed short
  URL ("thin.ly/launch") prominently in the lower half. The two
  options are visually balanced. Warm natural lighting, slight
  depth of field, editorial product-photo style.

### Inline 1 — Surfaces grid

- **Current**: `https://picsum.photos/seed/thinly-vs-surfaces/1200/675`
- **Target**: `/assets/images/qr-vs-link/surfaces.jpg`
- **Prompt**: A clean 2x3 grid of surface icons labeled "Podcast",
  "Poster", "Social post", "Email", "Conference badge", "Product
  packaging", each with a small badge indicating "Short link" or
  "QR code" or "Both". Modern editorial diagram style with violet
  accents.

### Inline 2 — Fallback short URL under QR

- **Current**: `https://picsum.photos/seed/thinly-vs-fallback/1200/675`
- **Target**: `/assets/images/qr-vs-link/fallback.jpg`
- **Prompt**: A close-up of a printed promotional card with a QR
  code centered and a clearly readable short URL ("thin.ly/menu")
  printed in slightly smaller type directly beneath it. The
  fallback URL is visually intentional, not an afterthought. Warm
  print-design aesthetic, slight paper texture.

### Inline 3 — Decision tree

- **Current**: `https://picsum.photos/seed/thinly-vs-decision/1200/675`
- **Target**: `/assets/images/qr-vs-link/decision.jpg`
- **Prompt**: A clean horizontal decision flowchart: start node
  asking "Can the user type this URL in 5 seconds without a
  mistake?" branching to two outcomes: "YES → Short link" and
  "NO → QR code + short URL fallback". Modern violet-accented
  diagram on a light background. Editorial style.

---

## How to swap an image

Once you've generated `assets/images/utm-parameters/hero.jpg`:

1. Save it under `blog/assets/images/utm-parameters/hero.jpg`
   (create the directory if it doesn't exist).
2. In the post file, change the `image:` frontmatter from
   `https://picsum.photos/seed/thinly-utm-hero/1600/900` to
   `/assets/images/utm-parameters/hero.jpg`.
3. Rebuild: `bin/build-blog` from the project root.

The same pattern applies to inline images — find the matching
`<figure><img src="https://picsum.photos/seed/...">` and replace
the `src` with the local path.

## Quick-swap script

If you want to bulk-swap all images at once after generating them,
this one-liner finds and rewrites every Picsum URL in the blog
posts (assuming you've named the local files to match the targets
listed above):

```bash
cd blog/_posts
for url in $(grep -roh "https://picsum.photos/seed/thinly-[^\"/]*" .); do
  slug=$(echo "$url" | sed 's|https://picsum.photos/seed/thinly-||')
  # Map slug → local path manually for the first run, then re-use this script
done
```

Easier in practice: search-and-replace per post in your editor.
