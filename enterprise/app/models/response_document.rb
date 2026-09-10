class ResponseDocument < ApplicationRecord
  has_many :responses, dependent: :destroy_async
  belongs_to :account
  belongs_to :response_source

  before_validation :set_account
  after_create :ensure_content
  after_update :handle_content_change

  private

  def set_account
    self.account = response_source.account
  end

  def ensure_content
    return unless content.nil?

    ResponseBot::ResponseDocumentContentJob.perform_later(self)
  end

  def handle_content_change
    return unless saved_change_to_content? && content.present?

    ResponseBot::ResponseBuilderJob.perform_later(self)
  end
end
