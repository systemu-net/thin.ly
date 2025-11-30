require "digest"
require "mini_magick"

class JdenticonGenerator
  AVATAR_SIZE = 200

  def initialize(identifier)
    @identifier = identifier
    @hash = Digest::MD5.hexdigest(identifier)
  end

  def generate
    svg_data = generate_jdenticon_svg
    png_data = convert_svg_to_png(svg_data)
    create_uploaded_file(png_data)
  end

  private

  def generate_jdenticon_svg
    # Generate a simple geometric pattern based on hash
    hue = @hash[0..1].to_i(16) * 360 / 255
    saturation = 50 + (@hash[2..3].to_i(16) * 30 / 255)
    lightness = 40 + (@hash[4..5].to_i(16) * 20 / 255)

    color = "hsl(#{hue}, #{saturation}%, #{lightness}%)"
    bg_lightness = 90 + (@hash[6..7].to_i(16) * 10 / 255)
    bg_color = "hsl(#{hue}, #{saturation}%, #{bg_lightness}%)"

    # Generate SVG with geometric shapes
    shapes = generate_shapes

    <<~SVG
      <svg width="#{AVATAR_SIZE}" height="#{AVATAR_SIZE}" xmlns="http://www.w3.org/2000/svg">
        <rect width="#{AVATAR_SIZE}" height="#{AVATAR_SIZE}" fill="#{bg_color}"/>
        #{shapes.map { |shape| render_shape(shape, color) }.join("\n  ")}
      </svg>
    SVG
  end

  def generate_shapes
    shapes = []

    # Generate a 5x5 grid pattern, mirrored for symmetry
    (0..2).each do |x|
      (0..4).each do |y|
        index = x * 5 + y
        if @hash[index].to_i(16) > 7
          # Add shape on left side
          shapes << { x: x, y: y, type: shape_type(index) }
          # Mirror to right side
          shapes << { x: 4 - x, y: y, type: shape_type(index) } unless x == 2
        end
      end
    end

    shapes
  end

  def shape_type(index)
    types = [ :rect, :circle, :triangle ]
    types[@hash[index + 10].to_i(16) % types.length]
  end

  def render_shape(shape, color)
    cell_size = AVATAR_SIZE / 5
    x = shape[:x] * cell_size
    y = shape[:y] * cell_size

    case shape[:type]
    when :rect
      %(<rect x="#{x}" y="#{y}" width="#{cell_size}" height="#{cell_size}" fill="#{color}" opacity="0.8"/>)
    when :circle
      cx = x + cell_size / 2
      cy = y + cell_size / 2
      r = cell_size / 2
      %(<circle cx="#{cx}" cy="#{cy}" r="#{r}" fill="#{color}" opacity="0.8"/>)
    when :triangle
      x1, y1 = x + cell_size / 2, y
      x2, y2 = x + cell_size, y + cell_size
      x3, y3 = x, y + cell_size
      %(<polygon points="#{x1},#{y1} #{x2},#{y2} #{x3},#{y3}" fill="#{color}" opacity="0.8"/>)
    end
  end

  def convert_svg_to_png(svg_data)
    # Create a temporary file for SVG
    svg_file = Tempfile.new([ "avatar", ".svg" ])
    svg_file.write(svg_data)
    svg_file.rewind
    svg_file.close

    # Convert SVG to PNG using MiniMagick
    image = MiniMagick::Image.open(svg_file.path)
    image.format "png"
    image.resize "#{AVATAR_SIZE}x#{AVATAR_SIZE}"

    png_data = image.to_blob

    svg_file.unlink
    png_data
  end

  def create_uploaded_file(png_data)
    tempfile = Tempfile.new([ "avatar", ".png" ])
    tempfile.binmode
    tempfile.write(png_data)
    tempfile.rewind

    ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: "avatar_#{@hash[0..7]}.png",
      type: "image/png"
    )
  end
end
