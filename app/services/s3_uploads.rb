# Thin wrapper around aws-sdk-s3 for presigned direct-to-S3 uploads and reading
# objects back (e.g. to hand them to Claude vision). Reuses the same bucket and
# credentials as the existing CarrierWave/fog-aws setup.
module S3Uploads
  module_function

  # content-type => extension for the image kinds we accept (and Claude supports)
  ALLOWED_TYPES = {
    "image/jpeg" => "jpg",
    "image/png" => "png",
    "image/gif" => "gif",
    "image/webp" => "webp"
  }.freeze

  def bucket
    ENV["S3_BUCKET"].presence || Rails.application.credentials.dig(:s3_bucket)
  end

  def region
    ENV["AWS_REGION"].presence || Rails.application.credentials.dig(:aws_region)
  end

  def access_key_id
    ENV["AWS_ACCESS_KEY_ID"].presence || Rails.application.credentials.dig(:aws_access_key_id)
  end

  def secret_access_key
    ENV["AWS_SECRET_ACCESS_KEY"].presence || Rails.application.credentials.dig(:aws_secret_access_key)
  end

  def configured?
    [bucket, region, access_key_id, secret_access_key].all?(&:present?)
  end

  def client
    @client ||= Aws::S3::Client.new(
      region: region,
      access_key_id: access_key_id,
      secret_access_key: secret_access_key
    )
  end

  def resource
    Aws::S3::Resource.new(client: client)
  end

  # Returns a presigned PUT url the browser uploads to directly, plus the public
  # url the object will be reachable at afterwards.
  def presign(content_type:, user_id:)
    ext = ALLOWED_TYPES[content_type]
    raise ArgumentError, "Unsupported image type" unless ext

    key = "uploads/ai_images/#{user_id}/#{SecureRandom.uuid}.#{ext}"
    obj = resource.bucket(bucket).object(key)
    {
      key: key,
      # Public read is granted by a bucket policy on the uploads/ prefix (see README),
      # not a per-object ACL — aws-sdk does not sign `x-amz-acl` into presigned PUTs.
      upload_url: obj.presigned_url(:put, expires_in: 300, content_type: content_type),
      public_url: obj.public_url.to_s,
      content_type: content_type
    }
  end

  # Reads an object back and returns [base64_data, media_type].
  def read_base64(key)
    resp = client.get_object(bucket: bucket, key: key)
    media_type = resp.content_type.presence || media_type_for(key)
    [Base64.strict_encode64(resp.body.read), media_type]
  end

  def media_type_for(key)
    ALLOWED_TYPES.key(File.extname(key).delete(".").downcase) || "image/jpeg"
  end
end
