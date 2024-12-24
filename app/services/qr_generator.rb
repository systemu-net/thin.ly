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
    qr_code = RQRCode::QRCode.new(link.shortened_url)

    # Convert QR code to PNG
    png_data = qr_code.as_png(
      bit_depth: 1,
      border_modules: 4,
      color_mode: ChunkyPNG::COLOR_GRAYSCALE,
      color: "black",
      file: nil,
      fill: "white",
      module_px_size: 11,
      resize_exactly_to: false,
      resize_gte_to: false,
      size: 120
    ).to_s

    # Write PNG data to a Tempfile
    tempfile.binmode # Ensure binary mode for writing
    tempfile.write(png_data)
    tempfile.rewind

    uploaded_file = ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: "#{link.lookup_code}.png",
      type: "image/png"
    )

    uploaded_file
  end

  def tempfile
    @tempfile ||= Tempfile.new([ "qrcode", ".png" ])
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
