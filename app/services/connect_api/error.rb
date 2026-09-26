# frozen_string_literal: true

module ConnectApi
  class Error < StandardError
    attr_reader :status, :payload

    def initialize(message, status: nil, payload: nil)
      super(message)
      @status = status
      @payload = payload
    end
  end
end
