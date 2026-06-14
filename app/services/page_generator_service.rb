# Generates a complete link-in-bio page spec from a natural-language prompt
# using Claude. Returns a plain hash (title/description/content/links/social) —
# it does NOT persist anything; the controller hands the spec to the client,
# which previews it and then creates the page via the normal APIs.
class PageGeneratorService
  MODEL = :"claude-opus-4-8"

  class GenerationError < StandardError; end

  BUTTON_SHAPES = %w[squared rounded-sm rounded rounded-lg rounded-full].freeze
  FONTS = ["rubik", "mono", "'Courier New', monospace", "'Brush Script MT', cursive"].freeze
  GRADIENT_DIRECTIONS = ["to right", "to bottom", "to top right", "to bottom left"].freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You design beautiful "link-in-bio" pages (like Linktree) from a short brief.
    Given a description of a person, brand, or project, produce ONE cohesive,
    tasteful page design by calling the `generate_page` tool exactly once.

    Design principles:
    - Pick a palette and typography that genuinely fit the brief's industry and mood.
      A wedding photographer, a fintech launch, and a punk band should look nothing alike.
    - NEVER default to generic "AI slop": avoid purple-on-white gradients unless the brief
      truly calls for it, avoid lorem-ipsum, avoid filler links.
    - Title: the name/brand (<= 40 chars). Description: a crisp tagline (<= 40 chars).
    - Propose 3-6 link buttons that a real page like this would have, with realistic,
      specific labels (not "Link 1"). Use plausible https URLs (the user will edit them).
    - Only include social handles that fit the brief; use full https URLs. Omit the rest.
    - All colors must be hex (e.g. "#1f2937").

    READABILITY — THIS IS NON-NEGOTIABLE. Every button label must be obviously legible.
    There is ONE shared button text color (`buttonColor`) used on EVERY button. Therefore:
    - `buttonColor` MUST have strong contrast (WCAG AA, ratio >= 4.5:1) against EVERY single
      link `color` (the button's background). A reader must see the label instantly.
    - Keep all button backgrounds in ONE consistent tone so one text color works for all:
      EITHER all dark-ish backgrounds with a light `buttonColor`,
      OR all light-ish backgrounds with a dark `buttonColor`.
      Do NOT mix near-black and near-white button backgrounds in the same page.
    - NEVER set a button background equal or nearly equal to `buttonColor`
      (no black text on a black button, no white text on a white button).
    - A bright "highlight" CTA button is encouraged, but it must STILL satisfy the 4.5:1
      rule with the same `buttonColor` (e.g. a neon-green button needs dark text, so if your
      other buttons are dark they should use the same dark text — keep the palette coherent).
    - `textColor` (page title/tagline) must likewise contrast strongly with the background.
    Before returning, mentally check each button: "Is the label clearly readable?" If not, fix it.

    IMAGES — if the user uploaded image(s) (shown above the brief, numbered #0, #1, …):
    - Build the ENTIRE palette (gradient/colors/button colors) from the images so the page feels
      designed around them — sample dominant and accent colors, match the mood.
    - If exactly one image is a strong portrait, headshot, or logo, set `profileImageIndex` to it.
      Otherwise leave `profileImageIndex` null.
    - If an image works as a striking full-bleed backdrop (a scene, texture, or hero shot — not a logo),
      set `backgroundType` to "image" and `backgroundImageIndex` to it. A dark gradient scrim is added
      automatically over background images for legibility, so use a LIGHT `textColor` (near-white) and
      light button text in that case. Otherwise leave `backgroundImageIndex` null and use color/gradient.
    - Use the SAME image for profile and background only if it genuinely suits both.
    - Refer to images strictly by their index; never invent image URLs.
    If no images were uploaded, ignore this section entirely.
  PROMPT

  PORTFOLIO_SYSTEM_PROMPT = <<~PROMPT.freeze
    You design award-winning, editorial single-page PORTFOLIO sites for individual
    creatives (designers, developers, photographers, studios) from a short brief.
    Call `generate_portfolio` exactly once with cohesive, specific, real-feeling content.

    Style & voice:
    - Confident, understated, editorial — like a high-end design studio. No filler, no lorem ipsum.
    - Write specific, believable project names and categories (not "Project 1").
    - Keep all copy tight: tagline <= 48 chars; statement one strong sentence; about = 1-2 short paragraphs.

    Fields:
    - name: the person/brand's full display name. firstName/lastName are the two big hero lines
      (usually first + last name, or a two-word brand). Keep each short (<= 8 chars renders best).
    - monogram: 2-4 char mark, e.g. initials "M.I".
    - eyebrow: their role, e.g. "Independent UI/UX Designer".
    - tagline: a short poetic positioning line.
    - location: "City, CC"; timezone: a valid IANA tz for that city (e.g. "Asia/Tokyo", "Europe/Berlin");
      coordinates: "35.0116° N / 135.7681° E" style; availability: e.g. "Booking Q3 — 2026".
    - statement: one editorial sentence about their craft.
    - about: 1-2 short paragraphs (strings).
    - work: 3-6 selected projects {title, category ("Sector · Discipline"), year}.
    - capabilities: 3-6 {title, description (one short sentence)}.
    - services: 4-6 short words for the scrolling marquee (e.g. "Interaction", "Art direction").
    - accent: ONE hex accent color that fits the field and is legible on a warm cream (#efeae0)
      background — choose a deep, saturated color (avoid pale/near-white). Default to a warm orange if unsure.
    - email: a plausible contact email; social: full https URLs only for platforms that fit.

    Derive everything from the brief and make it feel like one coherent, intentional brand.
  PROMPT

  def self.portfolio_tool_definition
    {
      name: "generate_portfolio",
      description: "Return a complete editorial portfolio page design.",
      input_schema: {
        type: "object",
        additionalProperties: false,
        required: %w[name eyebrow tagline accent work capabilities],
        properties: {
          name: { type: "string", description: "Full display name / brand" },
          firstName: { type: "string", description: "Hero line 1 (<= 8 chars ideal)" },
          lastName: { type: "string", description: "Hero line 2 (<= 8 chars ideal)" },
          monogram: { type: "string" },
          eyebrow: { type: "string" },
          tagline: { type: "string" },
          location: { type: "string" },
          timezone: { type: "string", description: "IANA timezone, e.g. Asia/Tokyo" },
          coordinates: { type: "string" },
          availability: { type: "string" },
          statement: { type: "string" },
          accent: { type: "string", description: "hex, deep & legible on cream" },
          email: { type: "string" },
          about: { type: "array", items: { type: "string" }, description: "1-2 short paragraphs" },
          services: { type: "array", items: { type: "string" }, description: "4-6 marquee words" },
          work: {
            type: "array",
            items: {
              type: "object", additionalProperties: false, required: %w[title category year],
              properties: { title: { type: "string" }, category: { type: "string" }, year: { type: "string" } }
            }
          },
          capabilities: {
            type: "array",
            items: {
              type: "object", additionalProperties: false, required: %w[title description],
              properties: { title: { type: "string" }, description: { type: "string" } }
            }
          },
          social: {
            type: "object", additionalProperties: false,
            properties: { fb: { type: "string" }, ig: { type: "string" }, x: { type: "string" }, linkedin: { type: "string" }, tiktok: { type: "string" } }
          }
        }
      }
    }
  end

  def self.tool_definition
    {
      name: "generate_page",
      description: "Return a complete link-in-bio page design.",
      input_schema: {
        type: "object",
        additionalProperties: false,
        required: %w[title description content links],
        properties: {
          title: { type: "string", description: "Brand or person name, max 40 chars" },
          description: { type: "string", description: "Short tagline, max 40 chars" },
          content: {
            type: "object",
            additionalProperties: false,
            required: %w[backgroundType textColor buttonColor button fontFamily],
            properties: {
              backgroundType: { type: "string", enum: %w[color gradient image] },
              backgroundColor: { type: "string", description: "hex, used when backgroundType=color" },
              gradientStart: { type: "string", description: "hex, used when backgroundType=gradient" },
              gradientEnd: { type: "string", description: "hex, used when backgroundType=gradient" },
              gradientDirection: { type: "string", enum: GRADIENT_DIRECTIONS },
              textColor: { type: "string", description: "hex" },
              buttonColor: { type: "string", description: "hex — the button label text color" },
              button: { type: "string", enum: BUTTON_SHAPES },
              fontFamily: { type: "string", enum: FONTS }
            }
          },
          links: {
            type: "array",
            description: "3-6 link buttons",
            items: {
              type: "object",
              additionalProperties: false,
              required: %w[title url color],
              properties: {
                title: { type: "string" },
                url: { type: "string" },
                color: { type: "string", description: "hex button background color" }
              }
            }
          },
          social: {
            type: "object",
            additionalProperties: false,
            description: "Only include platforms that fit; full https URLs.",
            properties: {
              fb: { type: "string" },
              ig: { type: "string" },
              x: { type: "string" },
              linkedin: { type: "string" },
              tiktok: { type: "string" }
            }
          },
          profileImageIndex: {
            type: %w[integer null],
            description: "Index (0-based) of the uploaded image to use as the profile/avatar photo, or null."
          },
          backgroundImageIndex: {
            type: %w[integer null],
            description: "Index (0-based) of the uploaded image to use as a full-bleed background (also set content.backgroundType to 'image'), or null."
          }
        }
      }
    }
  end

  # images: array of { "key" => s3_key, "url" => public_url } (max 3)
  # template: "links" (default) or "portfolio"
  def initialize(prompt:, name: nil, images: [], template: "links")
    # Generous server-side cap (the UI soft-limits the base prompt to 500; refine
    # appends to it). Bounds the payload defensively without affecting normal use.
    @prompt = prompt.to_s.strip[0, 4000]
    @name = name.to_s.strip[0, 120]
    @images = Array(images).first(3)
    @image_urls = []
    @template = template.to_s == "portfolio" ? "portfolio" : "links"
  end

  def call
    raise GenerationError, "Prompt is required" if @prompt.blank?

    portfolio = @template == "portfolio"
    tool = portfolio ? self.class.portfolio_tool_definition : self.class.tool_definition

    response = client.messages.create(
      model: MODEL,
      max_tokens: portfolio ? 3072 : 2048,
      system: portfolio ? PORTFOLIO_SYSTEM_PROMPT : SYSTEM_PROMPT,
      tools: [tool],
      tool_choice: { type: "tool", name: tool[:name] },
      messages: [{ role: "user", content: message_content }]
    )

    block = response.content.find { |b| b.type == :tool_use }
    raise GenerationError, "Model did not return a page design" unless block

    spec = deep_stringify(block.input)
    portfolio ? normalize_portfolio(spec) : normalize(spec)
  rescue Anthropic::Errors::APIError => e
    Rails.logger.error("PageGeneratorService Anthropic error: #{e.class}: #{e.message}")
    raise GenerationError, "The AI service is unavailable right now. Please try again."
  end

  private

  def client
    @client ||= begin
      api_key = ENV["ANTHROPIC_API_KEY"].presence ||
                Rails.application.credentials.dig(:anthropic_api_key)
      raise GenerationError, "ANTHROPIC_API_KEY is not configured" if api_key.blank?

      Anthropic::Client.new(api_key: api_key)
    end
  end

  # Builds the user turn — image blocks first (numbered), then the text brief.
  # Returns a plain string when there are no images.
  def message_content
    blocks = []
    @image_urls = []

    @images.each_with_index do |img, idx|
      key = img["key"] || img[:key]
      url = img["url"] || img[:url]
      next if key.blank?

      begin
        data, media_type = S3Uploads.read_base64(key)
      rescue StandardError => e
        Rails.logger.warn("PageGeneratorService: skipping image #{key}: #{e.message}")
        next
      end

      blocks << { type: "image", source: { type: "base64", media_type: media_type, data: data } }
      blocks << { type: "text", text: "↑ image ##{@image_urls.size}" }
      @image_urls << url
    end

    text = user_text(@image_urls.size)
    return text if blocks.empty?

    blocks << { type: "text", text: text }
    blocks
  end

  def user_text(image_count)
    parts = []
    parts << "Brand/name: #{@name}" if @name.present?
    parts << "Brief: #{@prompt}"
    if image_count.positive?
      parts << if @template == "portfolio"
        "The user uploaded #{image_count} image(s), shown above. Derive the accent color and mood " \
        "from them; they will be used as project thumbnails."
      else
        "The user uploaded #{image_count} image(s), shown above as #0..##{image_count - 1}. " \
        "Use them per the IMAGES rules: derive the palette from them, optionally use one as the " \
        "profile photo (profileImageIndex) and/or one as a full-bleed background " \
        "(backgroundImageIndex + backgroundType 'image')."
      end
    end
    parts.join("\n")
  end

  # block.input arrives with symbol or string keys depending on coercion; force strings.
  def deep_stringify(obj)
    case obj
    when Hash then obj.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
    when Array then obj.map { |v| deep_stringify(v) }
    else obj
    end
  end

  # Defensive: guarantee the shape the frontend expects, even if the model drifts.
  def normalize(spec)
    content = spec["content"] || {}
    result = {
      "title" => spec["title"].to_s[0, 40].presence || "Untitled",
      "description" => spec["description"].to_s[0, 40],
      "content" => {
        "backgroundType" => %w[color gradient image].include?(content["backgroundType"]) ? content["backgroundType"] : "gradient",
        "backgroundColor" => hex(content["backgroundColor"]) || "#0f172a",
        "gradientStart" => hex(content["gradientStart"]) || "#7c3aed",
        "gradientEnd" => hex(content["gradientEnd"]) || "#ec4899",
        "gradientDirection" => GRADIENT_DIRECTIONS.include?(content["gradientDirection"]) ? content["gradientDirection"] : "to bottom",
        "textColor" => hex(content["textColor"]) || "#ffffff",
        "buttonColor" => hex(content["buttonColor"]) || "#ffffff",
        "button" => BUTTON_SHAPES.include?(content["button"]) ? content["button"] : "rounded",
        "fontFamily" => FONTS.include?(content["fontFamily"]) ? content["fontFamily"] : "rubik",
        "social" => sanitize_social(spec["social"])
      },
      "links" => Array(spec["links"]).first(6).filter_map do |l|
        next unless l.is_a?(Hash)
        title = l["title"].to_s.strip
        url = l["url"].to_s.strip
        next if title.blank?

        { "title" => title, "url" => url.presence || "https://", "color" => hex(l["color"]) || "#3b82f6" }
      end
    }

    apply_image_roles!(result, spec)
    enforce_readability!(result)
    result
  end

  # Map the model's image indices to the actual uploaded S3 URLs.
  def apply_image_roles!(result, spec)
    content = result["content"]

    pi = spec["profileImageIndex"]
    content["profileImage"] = @image_urls[pi] if pi.is_a?(Integer) && @image_urls[pi].present?

    bi = spec["backgroundImageIndex"]
    if bi.is_a?(Integer) && @image_urls[bi].present?
      content["backgroundImage"] = @image_urls[bi]
      content["backgroundType"] = "image"
    elsif content["backgroundType"] == "image"
      # Model asked for an image background but gave no valid index — fall back.
      content["backgroundType"] = "gradient"
    end
  end

  # Build the portfolio content shape the template + frontend expect.
  def normalize_portfolio(spec)
    name = spec["name"].to_s.strip
    first = spec["firstName"].to_s.strip.presence || name.split.first.presence || "Studio"
    last  = spec["lastName"].to_s.strip.presence || name.split[1].presence || ""
    accent = hex(spec["accent"]) || "#e8541e"

    work = Array(spec["work"]).select { |w| w.is_a?(Hash) && w["title"].to_s.present? }.first(6).map do |w|
      { "title" => w["title"].to_s.strip, "category" => w["category"].to_s.strip, "year" => w["year"].to_s.strip }
    end
    # Attach uploaded images to the first work items as hover thumbnails.
    @image_urls.each_with_index { |url, i| work[i]["image"] = url if work[i] }

    caps = Array(spec["capabilities"]).select { |x| x.is_a?(Hash) && x["title"].to_s.present? }.first(6).map do |x|
      { "title" => x["title"].to_s.strip, "description" => x["description"].to_s.strip }
    end

    portfolio = {
      "monogram" => spec["monogram"].to_s.strip.presence || initials(name, first, last),
      "eyebrow" => spec["eyebrow"].to_s.strip.presence || "Independent Designer",
      "firstName" => first[0, 18],
      "lastName" => last[0, 18],
      "tagline" => spec["tagline"].to_s.strip[0, 80],
      "location" => spec["location"].to_s.strip.presence || "",
      "timezone" => spec["timezone"].to_s.strip.presence || "UTC",
      "coordinates" => spec["coordinates"].to_s.strip,
      "availability" => spec["availability"].to_s.strip.presence || "Available for work",
      "statement" => spec["statement"].to_s.strip,
      "about" => Array(spec["about"]).map { |p| p.to_s.strip }.reject(&:blank?).first(2),
      "services" => Array(spec["services"]).map { |s| s.to_s.strip }.reject(&:blank?).first(8),
      "work" => work,
      "capabilities" => caps,
      "email" => spec["email"].to_s.strip
    }

    {
      "title" => name.presence || "#{first} #{last}".strip,
      "description" => portfolio["tagline"],
      "content" => {
        "template" => "portfolio",
        "accent" => accent,
        "portfolio" => portfolio,
        "social" => sanitize_social(spec["social"])
      }
    }
  end

  def initials(name, first, last)
    src = name.presence || "#{first} #{last}"
    parts = src.split.map { |w| w[0] }.compact
    (parts.first(2).join(".") + ".").upcase
  end

  # ── Contrast guardrail ──────────────────────────────────────────────────────
  # Mathematically guarantees that every button label and the page text are
  # readable (WCAG AA), regardless of what the model returned. This is the hard
  # safety net behind the prompt rules.
  MIN_CONTRAST = 4.5

  def enforce_readability!(result)
    content = result["content"]
    links = result["links"]

    if links.any?
      # Pick the single button text color that reads on the MOST buttons as-is
      # (so we keep the dominant aesthetic), preferring the model's own choice on ties.
      candidates = [content["buttonColor"], "#111111", "#ffffff"].compact.uniq
      content["buttonColor"] = candidates.max_by do |tc|
        passing = links.count { |l| contrast_ratio(l["color"], tc) >= MIN_CONTRAST }
        avg = links.sum { |l| contrast_ratio(l["color"], tc) } / links.size
        [passing, avg]
      end

      # Fix any remaining low-contrast buttons by nudging their background away
      # from the text color until the label is legible (hue preserved as much as possible).
      links.each do |l|
        next if contrast_ratio(l["color"], content["buttonColor"]) >= MIN_CONTRAST

        l["color"] = nudge_for_contrast(l["color"], content["buttonColor"], MIN_CONTRAST)
      end
    end

    # Image backgrounds get a dark scrim in the renderer, so light text always reads.
    if content["backgroundType"] == "image"
      content["textColor"] = "#ffffff" if relative_luminance(content["textColor"]) < 0.6
      return
    end

    # Page title/tagline must read on the background.
    bg = background_base(content)
    if contrast_ratio(content["textColor"], bg) < MIN_CONTRAST
      content["textColor"] = best_text_on(bg)
    end
  end

  # Representative background color (gradient → midpoint blend) for contrast checks.
  def background_base(content)
    if content["backgroundType"] == "gradient"
      blend(content["gradientStart"], content["gradientEnd"], 0.5)
    else
      content["backgroundColor"]
    end
  end

  def best_text_on(bg)
    contrast_ratio("#ffffff", bg) >= contrast_ratio("#111111", bg) ? "#ffffff" : "#111111"
  end

  # Blend `bg` toward black or white (whichever raises contrast vs `text`) until
  # the ratio is met, in small steps so the hue is preserved where possible.
  def nudge_for_contrast(bg, text, target)
    toward = relative_luminance(text) > 0.5 ? [0, 0, 0] : [255, 255, 255]
    rgb = to_rgb(bg)
    18.times do
      return to_hex(rgb) if contrast_ratio(to_hex(rgb), text) >= target

      rgb = rgb.each_with_index.map { |c, i| (c + (toward[i] - c) * 0.12).round }
    end
    to_hex(rgb)
  end

  def blend(a, b, t)
    ra = to_rgb(a)
    rb = to_rgb(b)
    to_hex(ra.each_with_index.map { |c, i| (c + (rb[i] - c) * t).round })
  end

  def contrast_ratio(c1, c2)
    l1 = relative_luminance(c1)
    l2 = relative_luminance(c2)
    hi = [l1, l2].max
    lo = [l1, l2].min
    (hi + 0.05) / (lo + 0.05)
  end

  def relative_luminance(color)
    r, g, b = to_rgb(color).map do |c|
      cs = c / 255.0
      cs <= 0.03928 ? cs / 12.92 : ((cs + 0.055) / 1.055)**2.4
    end
    (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
  end

  # Parse #rgb / #rrggbb (ignoring alpha) into [r,g,b]; falls back to mid-gray.
  def to_rgb(color)
    s = color.to_s.delete("#")
    s = s.chars.map { |ch| ch * 2 }.join if s.length == 3
    return [128, 128, 128] unless s.length >= 6

    [s[0, 2], s[2, 2], s[4, 2]].map { |h| h.to_i(16) }
  end

  def to_hex(rgb)
    "#" + rgb.map { |c| c.clamp(0, 255).to_s(16).rjust(2, "0") }.join
  end

  def sanitize_social(social)
    return {} unless social.is_a?(Hash)

    %w[fb ig x linkedin tiktok].each_with_object({}) do |k, h|
      v = social[k].to_s.strip
      h[k] = v if v.start_with?("http")
    end
  end

  def hex(value)
    s = value.to_s.strip
    s.match?(/\A#[0-9a-fA-F]{3,8}\z/) ? s : nil
  end
end
