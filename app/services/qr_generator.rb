require "rqrcode"
require "ostruct"

# Define a custom error response object
class ErrorResponse < OpenStruct
  def full_messages
    errors.map { |field, message| "#{field.to_s.humanize} #{message}" }
  end
end

class QrGenerator
  attr_reader :original_url, :lookup_code, :user_id, :link_model

  def initialize(original_url, lookup_code, user_id, link_model = Link)
    @original_url = original_url
    @lookup_code = lookup_code
    @user_id = user_id
    @link_model = link_model
  end

  def generate_qr_code
    return OpenStruct.new(errors: ErrorResponse.new(errors: { link: "cannot be found" })) unless link

    qr_code = link.qr_codes.create(image: qr_code_svg, user_id: user_id)
    tempfile.close
    tempfile.unlink
    qr_code
  end

  def qr_code_svg
    # Add ?r=qr query parameter to track QR code scans
    qr_code_url = "#{link.shortened_url}?r=qr"

    # Use high error correction (:h = 30% damage tolerance) to allow logo overlay
    qr_code = RQRCode::QRCode.new(qr_code_url, level: :h)

    # Generate SVG for infinite scalability and smaller file size
    svg_data = qr_code.as_svg(
      color: "000",           # Black modules (hex without #)
      shape_rendering: "crispEdges",  # Sharp edges for QR codes
      module_size: 6,         # Size of each QR module in SVG units
      standalone: true,       # Include XML declaration
      use_path: true          # Use path instead of rects (smaller file size)
    )

    # Embed thin.ly logo in the center of QR code
    svg_with_logo = embed_logo_in_qr_code(svg_data, qr_code.modules.size)

    # Write SVG data to a Tempfile
    tempfile.write(svg_with_logo)
    tempfile.rewind

    uploaded_file = ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: "#{link.lookup_code}.svg",
      type: "image/svg+xml"
    )

    uploaded_file
  end

  private

  def embed_logo_in_qr_code(svg_data, module_count)
    # Calculate QR code dimensions
    module_size = 6  # Must match the module_size in as_svg above
    qr_size = module_count * module_size

    # Logo should be ~20% of QR code size (safe for high error correction)
    logo_size = qr_size * 0.2
    logo_x = (qr_size - logo_size) / 2
    logo_y = (qr_size - logo_size) / 2

    # Read the thin.ly logo from public/icon.svg
    logo_path = Rails.root.join("public", "icon.svg")
    logo_content = File.read(logo_path)

    # Build logo overlay with white rounded rectangle background and embedded logo
    logo_overlay = <<~LOGO
  <!-- thin.ly Logo Overlay -->
  <g id="logo-overlay">
    <rect x="#{logo_x - 4}" y="#{logo_y - 4}"#{' '}
          width="#{logo_size + 8}" height="#{logo_size + 8}"#{' '}
          fill="white" stroke="black" stroke-width="2" rx="8" ry="8"/>
    <image href="data:image/svg+xml;base64,#{Base64.strict_encode64(logo_content)}"#{' '}
           x="#{logo_x}" y="#{logo_y}"#{' '}
           width="#{logo_size}" height="#{logo_size}"/>
  </g>
    LOGO

    # Insert logo before closing </svg> tag
    svg_data.sub("</svg>", "#{logo_overlay}\n</svg>")
  end

  def tempfile
    @tempfile ||= Tempfile.new([ "qrcode", ".svg" ])
  end

  def link
    @link ||= if lookup_code
      link_model.find_by(lookup_code: lookup_code)
    else
      shortener = Shortener.new(original_url, user_id) if original_url
      @link = shortener&.generate_short_link
    end
  end
end
