#!/usr/bin/env python3
"""
Generate the 32 blog post images via fal.ai FLUX-pro v1.1.

Pricing (May 2026): $0.04 per megapixel, rounded up to nearest MP.
  - Heroes:  1600x900 ~= 1.44 MP -> rounds to 2 MP -> $0.08 each
  - Inline:  1200x675 ~= 0.81 MP -> rounds to 1 MP -> $0.04 each
Total for 32 images: 8 * $0.08 + 24 * $0.04 = $1.60.

Auth: export FAL_KEY=your-key-here before running. Get a key at
https://fal.ai/dashboard/keys.

Usage:
    export FAL_KEY=...
    python3 blog/scripts/generate_falai.py

Re-runs are safe: existing files >5KB are skipped. Delete a file to
regenerate it. Use --force to regenerate everything.

Pass --only PATH_FRAGMENT to limit to a subset (e.g. --only hero will
regenerate only the 8 hero images).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

FAL_ENDPOINT = "https://fal.run/fal-ai/flux-pro/v1.1"

# Same style guide we'd send to any AI image model. Keeps the 32 images
# visually coherent across the blog.
STYLE_PREFIX = (
    "Editorial illustration in a clean, modern, slightly muted style. "
    "Soft natural lighting. Generous negative space. Brand accent color "
    "is violet (#6d28d9, #7c3aed). Avoid cliched stock-photography tropes "
    "- no high-fives, no people pointing at laptops, no blueprint hands. "
    "Avoid heavy text overlays; if any text is shown in the image, keep "
    "it short and legible. 16:9 aspect ratio, photorealistic or 3D render "
    "quality, not flat vector art. "
)

# (rel_path, width, height, prompt)
IMAGES = [
    # Post 1 - UTM Parameters
    ("utm-parameters/hero.jpg", 1600, 900,
        "An editorial overhead shot of a desktop workspace with a large "
        "laptop screen showing a colorful analytics dashboard. Multiple "
        "campaign cards visible with click counts and percentage changes. "
        "Coffee cup, notebook, and a smartphone with a similar dashboard "
        "view nearby. Muted natural light from a window on the left. "
        "Violet accents in the dashboard visuals."),
    ("utm-parameters/utm-stack.jpg", 1200, 675,
        "A clean 3D-rendered diagram showing layered translucent cards: "
        "top card labeled 'Short link wrapper' with a thin.ly-style URL, "
        "second card 'Destination URL' with a longer path, third card "
        "'UTM parameters' with key/value chips. The cards are stacked "
        "with visible depth, soft purple gradient background."),
    ("utm-parameters/vocabulary.jpg", 1200, 675,
        "Close-up of a whiteboard or notebook page with a hand-written "
        "marketing UTM convention list. Pen resting on the notebook. "
        "Soft daylight from one side. Subtle violet highlighter marks "
        "on key terms."),
    ("utm-parameters/workflow.jpg", 1200, 675,
        "A clean, modern process diagram with four numbered steps "
        "connected by arrows: 1 Campaign brief, 2 Tagged destination "
        "URL, 3 Shortened link, 4 Attributed click in analytics. Each "
        "step shown as an icon-and-label card. Violet accent color on "
        "the arrows. Light grey background. Minimalist."),

    # Post 2 - QR Codes for Print
    ("qr-codes-for-print/hero.jpg", 1600, 900,
        "Photorealistic close-up of a printed event poster on a wall, "
        "with a large QR code prominently in the lower right and a short "
        "URL printed clearly underneath. A hand is holding a smartphone "
        "framing the QR code, mid-scan. Warm gallery lighting. Shallow "
        "depth of field with the QR code in sharp focus."),
    ("qr-codes-for-print/dynamic-vs-static.jpg", 1200, 675,
        "Side-by-side comparison illustration: left half labeled STATIC "
        "showing a printed QR code with a broken or error icon on the "
        "destination screen; right half labeled DYNAMIC showing the same "
        "printed QR code but the destination screen has been updated to "
        "a new campaign. Subtle violet accent labels. Clean editorial "
        "design."),
    ("qr-codes-for-print/sizing.jpg", 1200, 675,
        "A hotel lobby with a large vertical advertising poster on a "
        "stand, a large QR code prominently displayed at viewing height, "
        "a person standing across the room about three meters away "
        "holding up their phone to scan. The scale relationship between "
        "viewer distance and QR code size is clear."),
    ("qr-codes-for-print/context.jpg", 1200, 675,
        "A printed restaurant table card or menu showing a QR code with "
        "clear friendly text above it (scan to see the wine list). Warm "
        "restaurant lighting, slight depth of field, the card framed by "
        "a partial place setting. Editorial food-magazine style."),

    # Post 3 - Link Analytics
    ("link-analytics/hero.jpg", 1600, 900,
        "A wide editorial shot of a modern analytics dashboard on a "
        "large monitor: a line chart of clicks over time, a small world "
        "map with country click densities, a device-split donut chart, "
        "and a referrer table. Violet brand accent on key metrics. "
        "Slightly off-axis composition with a coffee mug and notebook in "
        "the foreground, suggesting a marketer reviewing data."),
    ("link-analytics/uniques.jpg", 1200, 675,
        "A side-by-side comparison of two line charts on a clean "
        "dashboard interface: one labeled 'Total clicks' (higher line), "
        "one labeled 'Unique clicks' (lower line, parallel). The gap "
        "between them is shaded subtly. Violet accent on the unique "
        "line. Minimalist, editorial."),
    ("link-analytics/geo.jpg", 1200, 675,
        "A world map shown as a clean choropleth heatmap with click "
        "densities indicated by color intensity (light cream to deep "
        "violet). Sparse country labels for the highest-density regions. "
        "Subtle grid background. Dashboard-card style framing."),
    ("link-analytics/hourly.jpg", 1200, 675,
        "A 24-hour bar histogram showing click distribution by hour of "
        "day, with a clear working-hours peak (9am-6pm) and a small "
        "late-evening secondary peak. Violet bars on a soft grey "
        "background. Hour labels on x-axis, 'Clicks' label on y-axis. "
        "Clean dashboard chart aesthetic."),

    # Post 4 - URL Shortener Security
    ("url-shortener-security/hero.jpg", 1600, 900,
        "A photorealistic abstract concept of digital trust: a glowing "
        "padlock icon floating above a network of soft-glowing connection "
        "lines representing URL redirects. Deep dark navy background "
        "with violet and cyan accent glows. Cinematic lighting. Modern "
        "3D-art style, not clipart."),
    ("url-shortener-security/threats.jpg", 1200, 675,
        "A clean grid of four threat-icon cards labeled: Malware, "
        "Phishing, Scams, Policy violations. Each card has a minimalist "
        "warning icon and a soft red or orange accent. Editorial diagram "
        "style on a light background."),
    ("url-shortener-security/scanning.jpg", 1200, 675,
        "An abstract diagram showing a URL passing through several "
        "layered scanner panels labeled with names like Safe Browsing, "
        "Heuristic check, Sandboxed inspection. Each panel adds a check "
        "mark or annotation as the URL passes through. Modern "
        "glassmorphism style with violet gradient accents."),
    ("url-shortener-security/interstitial.jpg", 1200, 675,
        "A laptop screen displaying a clean, friendly safety warning "
        "page: a shield icon, headline 'This link was flagged as "
        "unsafe', explanatory body text, and a 'Report a false positive' "
        "button. The browser address bar shows a thin.ly short URL. "
        "Soft natural lighting. Photographed from a slight angle."),

    # Post 5 - Branded vs Generic
    ("branded-vs-generic/hero.jpg", 1600, 900,
        "A large outdoor billboard in a city at golden hour, displaying "
        "a campaign with a branded short URL (e.g. acme.link/launch) "
        "prominently centered. The billboard's brand identity is clear. "
        "Wide cinematic shot looking up at the billboard. Warm light, "
        "deep shadows. Photorealistic."),
    ("branded-vs-generic/trust.jpg", 1200, 675,
        "A smartphone screen split-screen showing two link previews "
        "side by side: left one shows a generic-shortener URL, right "
        "one shows a branded URL. A subtle 'more trusted' annotation on "
        "the branded side. Clean modern UI. Editorial product-photography "
        "style."),
    ("branded-vs-generic/cost.jpg", 1200, 675,
        "A clean horizontal bar-chart illustration showing cost "
        "categories for branded domain setup: 'Domain registration', "
        "'Plan tier', 'DNS/SSL', 'Internal coordination'. Bars in "
        "graduated violet shades. Soft grey background. Dashboard-style."),
    ("branded-vs-generic/subdomain.jpg", 1200, 675,
        "A clean UI mockup of a 'Custom domain' configuration panel "
        "inside a modern SaaS product: input field showing a subdomain, "
        "a status badge 'Verified, SSL active', and a 'Save' button in "
        "violet. Soft drop shadows. Light theme."),

    # Post 6 - Link Governance
    ("link-governance/hero.jpg", 1600, 900,
        "A wide editorial shot of a modern audit-log interface on a "
        "monitor: timeline view with state-change entries (paused, "
        "resumed, destination changed, expired), each entry tagged with "
        "a user avatar and timestamp. Violet accent on the most recent "
        "entry. Slightly off-axis composition with a desk plant and "
        "coffee mug in the soft foreground."),
    ("link-governance/pause.jpg", 1200, 675,
        "A close-up UI mockup of a link's dashboard row with a clearly "
        "visible 'Paused' status badge in soft amber and a 'Resume' "
        "button highlighted in violet. The click-count number is "
        "preserved next to the status. Modern, clean SaaS aesthetic."),
    ("link-governance/routing.jpg", 1200, 675,
        "A flow diagram showing a single short link branching into "
        "three destinations based on conditions: if country = EU, if "
        "device = mobile, default. Clean diagram with violet condition "
        "branches. Light theme."),
    ("link-governance/audit.jpg", 1200, 675,
        "A vertical timeline UI showing successive link events: Created, "
        "Destination updated, Paused, Resumed - each with a small avatar "
        "and timestamp. Clean modern interface on a light background."),

    # Post 7 - Custom Domains
    ("custom-domains/hero.jpg", 1600, 900,
        "A close-up of a DNS zone editor on a developer's monitor: rows "
        "of records (A, CNAME, TXT) with editable fields. One CNAME "
        "record is highlighted in violet, mid-edit. Slight bokeh in the "
        "background suggesting a development environment. Modern editor "
        "aesthetic."),
    ("custom-domains/picking.jpg", 1200, 675,
        "A clean grid of candidate short-domain options across multiple "
        "TLDs: 'acme.link', 'acme.co', 'acme.io', 'go.acme.com', each "
        "with a small 'available' or 'taken' indicator. Modern "
        "domain-search UI mockup. Violet accents on available results."),
    ("custom-domains/dns.jpg", 1200, 675,
        "A clean table-style UI showing DNS records for a short domain: "
        "CNAME record pointing to a target, two A records, a TXT "
        "verification record. Each row has a small status indicator. "
        "Modern admin-panel aesthetic on a light background. Violet "
        "accents."),
    ("custom-domains/ssl.jpg", 1200, 675,
        "A close-up of a browser's address bar showing an HTTPS URL "
        "with a green padlock icon and a valid certificate tooltip "
        "showing 'Connection is secure, Issued by Let's Encrypt'. Clean "
        "modern browser UI. Soft natural lighting on the laptop screen."),

    # Post 8 - QR vs Short Link
    ("qr-vs-link/hero.jpg", 1600, 900,
        "Photorealistic close-up of a printed marketing card or poster "
        "showing a QR code in the upper half and a printed short URL "
        "prominently in the lower half. The two options are visually "
        "balanced. Warm natural lighting, slight depth of field, "
        "editorial product-photo style."),
    ("qr-vs-link/surfaces.jpg", 1200, 675,
        "A clean 2x3 grid of surface icons labeled: Podcast, Poster, "
        "Social post, Email, Conference badge, Product packaging, each "
        "with a small badge indicating 'Short link' or 'QR code' or "
        "'Both'. Modern editorial diagram style with violet accents."),
    ("qr-vs-link/fallback.jpg", 1200, 675,
        "A close-up of a printed promotional card with a QR code "
        "centered and a clearly readable short URL printed in slightly "
        "smaller type directly beneath it. The fallback URL is visually "
        "intentional, not an afterthought. Warm print-design aesthetic, "
        "slight paper texture."),
    ("qr-vs-link/decision.jpg", 1200, 675,
        "A clean horizontal decision flowchart: start node asking 'Can "
        "the user type this URL in 5 seconds without a mistake?' "
        "branching to two outcomes: YES leading to 'Short link' and NO "
        "leading to 'QR code plus short URL fallback'. Modern violet-"
        "accented diagram on a light background. Editorial style."),
]


def call_fal(prompt: str, width: int, height: int, seed: int, key: str) -> str:
    """Call fal.ai FLUX-pro v1.1, return URL of generated image."""
    payload = {
        "prompt": STYLE_PREFIX + prompt,
        "image_size": {"width": width, "height": height},
        "seed": seed,
        "num_images": 1,
        "enable_safety_checker": False,
        "safety_tolerance": "5",
        "output_format": "jpeg",
    }
    req = urllib.request.Request(
        FAL_ENDPOINT,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Key {key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    images = data.get("images", [])
    if not images:
        raise RuntimeError(f"no images in response: {data!r}")
    url = images[0].get("url")
    if not url:
        raise RuntimeError(f"no url in image: {images[0]!r}")
    return url


def download(url: str, target: Path) -> int:
    """Download an image from URL to target path. Return bytes written."""
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "thin.ly-blog-image-gen/1.0"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = resp.read()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    return len(data)


def fetch_one(target: Path, w: int, h: int, prompt: str, seed: int, key: str,
              force: bool) -> tuple[Path, bool, str]:
    """Generate + download one image. Returns (path, ok, message)."""
    if not force and target.exists() and target.stat().st_size > 5000:
        return target, True, "skipped (exists)"
    try:
        url = call_fal(prompt, w, h, seed, key)
        size = download(url, target)
        return target, True, f"{size // 1024} KB"
    except urllib.error.HTTPError as exc:
        body = ""
        try:
            body = exc.read().decode("utf-8", errors="replace")[:200]
        except Exception:
            pass
        return target, False, f"HTTP {exc.code}: {body}"
    except Exception as exc:  # noqa: BLE001
        return target, False, f"{type(exc).__name__}: {exc}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true",
                        help="regenerate even if file exists")
    parser.add_argument("--only", default=None,
                        help="only generate images whose path contains this fragment")
    parser.add_argument("--concurrency", type=int, default=4,
                        help="parallel requests to fal.ai (default 4)")
    args = parser.parse_args()

    key = os.environ.get("FAL_KEY", "").strip()
    if not key:
        print("ERROR: FAL_KEY env var is not set.", file=sys.stderr)
        print("Get a key at https://fal.ai/dashboard/keys then:", file=sys.stderr)
        print("    export FAL_KEY=your-key", file=sys.stderr)
        return 2

    root = Path(__file__).resolve().parent.parent / "assets" / "images"
    jobs = []
    for idx, (rel, w, h, prompt) in enumerate(IMAGES):
        if args.only and args.only not in rel:
            continue
        target = root / rel
        jobs.append((target, w, h, prompt, 1000 + idx))

    if not jobs:
        print("No jobs matched --only filter.")
        return 1

    print(f"Generating {len(jobs)} images into {root}/")
    print(f"Concurrency: {args.concurrency}.  Force: {args.force}.")
    start = time.time()

    successes, failures = [], []
    with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        futs = {
            pool.submit(fetch_one, t, w, h, p, s, key, args.force): t
            for (t, w, h, p, s) in jobs
        }
        for fut in as_completed(futs):
            tgt = futs[fut]
            path, ok, msg = fut.result()
            rel_path = path.relative_to(root)
            if ok:
                successes.append(rel_path)
                print(f"  ok   {str(rel_path):50s} {msg}")
            else:
                failures.append(rel_path)
                print(f"  FAIL {str(rel_path):50s} {msg}")

    elapsed = time.time() - start
    print()
    print(f"Done in {elapsed:.1f}s: {len(successes)} ok, {len(failures)} failed.")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
