class InboxResponseSource < ApplicationRecord
  belongs_to :inbox
  belongs_to :response_source
end
