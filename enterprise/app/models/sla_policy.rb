class SlaPolicy < ApplicationRecord
  belongs_to :account
  validates :name, presence: true

  has_many :conversations, dependent: :nullify
  has_many :applied_slas, dependent: :destroy

  def push_event_data
    {
      id: id,
      name: name,
      frt: first_response_time_threshold,
      nrt: next_response_time_threshold,
      rt: resolution_time_threshold
    }
  end
end
