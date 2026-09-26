require 'digest'
require 'uri'

class WorkspaceApp < ApplicationRecord
  ICON_NAMES = %w[globe briefcase calendar mail chat-multiple people document key settings].freeze
  LOGIN_FIELD = /\A[a-zA-Z][a-zA-Z0-9_\[\]-]{0,79}\z/
  RESERVED_FIELDS = %w[action method target submit enctype _method authenticity_token].freeze
  INTEGRATION_FIELDS = %w[url launch_mode auth_mode login_url username_field password_field].freeze

  belongs_to :account
  has_one_attached :icon
  has_many :workspace_app_credentials, dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }
  validates :icon_name, inclusion: { in: ICON_NAMES }
  validates :launch_mode, inclusion: { in: %w[embedded external] }
  validates :auth_mode, inclusion: { in: %w[session form_post] }
  validates :access_mode, inclusion: { in: %w[everyone administrators selected] }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 100_000 }
  validates :enabled, :allow_saved_credentials, :allow_auto_login, inclusion: { in: [true, false] }
  validate :validate_destinations
  validate :validate_authentication
  validate :validate_allowed_users
  validate :validate_icon
  after_update :revoke_changed_credentials

  scope :ordered, -> { order(:position, :id) }

  def accessible_to?(membership)
    return false unless membership && membership.account_id == account_id
    return true if membership.administrator?

    access_mode == 'everyone' || (access_mode == 'selected' && allowed_user_ids.include?(membership.user_id))
  end

  def integration_revision
    Digest::SHA256.hexdigest(INTEGRATION_FIELDS.map { |field| self[field] }.to_json)
  end

  def origin(value)
    uri = URI.parse(value.to_s)
    return unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && uri.port.between?(1, 65_535)

    "#{uri.scheme}://#{uri.host.downcase}:#{uri.port}"
  rescue URI::Error
    nil
  end

  private

  def validate_destinations
    errors.add(:url, 'must be an HTTPS URL without embedded credentials') unless valid_url?(url)
    if auth_mode == 'form_post'
      errors.add(:login_url, 'must be an HTTPS URL on the application origin, without a fragment') unless
        valid_url?(login_url) && origin(login_url) == origin(url) && URI.parse(login_url).fragment.nil?
    end
    hub_origin = origin(ENV.fetch('FRONTEND_URL', ''))
    if launch_mode == 'embedded' && hub_origin && origin(url) == hub_origin
      errors.add(:url, 'must use a different origin from the HUB')
    end
  end

  def valid_url?(value)
    value.is_a?(String) && value.length <= 2048 && !value.match?(/[\s\\\x00-\x1f]/) && origin(value).present?
  end

  def validate_authentication
    if auth_mode == 'form_post'
      errors.add(:launch_mode, 'must be embedded for POST authentication') unless launch_mode == 'embedded'
      %i[username_field password_field].each do |field|
        value = self[field].to_s
        errors.add(field, 'is not a supported form field') unless value.match?(LOGIN_FIELD) && RESERVED_FIELDS.exclude?(value.downcase)
      end
      errors.add(:password_field, 'must differ from the username field') if username_field == password_field
    elsif allow_saved_credentials || allow_auto_login
      errors.add(:auth_mode, 'must be form_post to store or submit credentials')
    end
    errors.add(:allow_auto_login, 'requires saved credentials to be allowed') if allow_auto_login && !allow_saved_credentials
  end

  def validate_allowed_users
    ids = allowed_user_ids
    unless ids.is_a?(Array) && ids.size <= 1000 && ids.all? { |id| id.is_a?(Integer) && id.positive? } && ids.uniq == ids
      errors.add(:allowed_user_ids, 'must contain distinct user IDs')
      return
    end
    return if ids.empty?

    errors.add(:allowed_user_ids, 'contains users outside this company') unless account && account.account_users.where(user_id: ids).count == ids.length
  end

  def validate_icon
    return unless icon.attached?

    errors.add(:icon, 'must be PNG, JPEG or WebP') unless %w[image/png image/jpeg image/webp].include?(icon.blob.content_type)
    errors.add(:icon, 'must not exceed 1 MB') if icon.blob.byte_size > 1.megabyte
  end

  def revoke_changed_credentials
    if (saved_changes.keys & INTEGRATION_FIELDS).any? || !allow_saved_credentials
      workspace_app_credentials.delete_all
    elsif saved_change_to_allow_auto_login? && !allow_auto_login
      workspace_app_credentials.update_all(auto_login: false)
    end
  end
end
