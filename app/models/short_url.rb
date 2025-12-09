class ShortUrl < ApplicationRecord
  belongs_to :user

  validates :url1, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid URL" }
  validates :url2, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid URL" }, allow_blank: true
  validates :short_uri, presence: true, uniqueness: true, format: { with: /\A[a-zA-Z0-9_-]+\z/, message: "can only contain letters, numbers, hyphens, and underscores" }

  before_validation :normalize_urls
  before_create :generate_tracking_id

  private

  def normalize_urls
    self.url1 = url1.strip if url1.present?
    self.url2 = url2.strip if url2.present?
    self.short_uri = short_uri.strip.downcase if short_uri.present?
  end

  def generate_tracking_id
    # Generate a 32-character hex string (like: 00c8328e409c4831e4aba4f65ec3a0c1)
    self.tracking_id ||= SecureRandom.hex(16)
  end
end
