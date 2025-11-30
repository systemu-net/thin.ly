class AvatarUploader < CarrierWave::Uploader::Base
  # Include MiniMagick for image processing
  include CarrierWave::MiniMagick

  # Storage is configured globally in config/initializers/carrierwave.rb
  # Test environment uses :file, production/development uses :fog (S3)

  # Override the directory where uploaded files will be stored.
  def store_dir
    "uploads/#{model.class.to_s.underscore}/#{mounted_as}/#{model.id}"
  end

  # Process images: resize first, then convert to WebP and optimize
  process resize_to_fill: [ 400, 400 ]  # Square avatar, 400x400px
  process :convert_and_optimize

  # Create thumbnail version for faster loading in lists/navigation
  version :thumb do
    process resize_to_fill: [ 100, 100 ]
  end

  # Add an allowlist of extensions which are allowed to be uploaded.
  def extension_allowlist
    %w[jpg jpeg gif png webp heic heif]
  end

  # Content type allowlist
  def content_type_allowlist
    /image\//
  end

  # File size limit (5MB)
  def size_range
    1..5.megabytes
  end

  # Override the filename to always use .webp extension
  def filename
    "avatar.webp"
  end

  # Set correct content type for S3
  def fog_attributes
    {
      "Content-Type" => "image/webp",
      "Cache-Control" => "public, max-age=#{365.days.to_i}"
    }
  end

  # Override content type to always be webp
  def content_type
    "image/webp"
  end

  private

  # Convert image to WebP format and optimize
  def convert_and_optimize
    manipulate! do |img|
      # Auto-orient based on EXIF data (important for mobile photos)
      img.auto_orient

      # Convert to WebP
      img.format("webp")

      # Strip metadata
      img.strip

      # Set quality
      img.quality(85)

      img
    end
  end

  def secure_token
    var = :"@#{mounted_as}_secure_token"
    model.instance_variable_get(var) or model.instance_variable_set(var, SecureRandom.uuid)
  end
end
