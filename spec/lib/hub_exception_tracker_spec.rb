require 'rails_helper'

RSpec.describe HubExceptionTracker do
  describe '#capture_exception' do
    it 'logs exceptions and metadata locally without using a remote tracker' do
      exception = StandardError.new('local failure')
      allow(exception).to receive(:backtrace).and_return(['line 1'])
      allow(Rails.logger).to receive(:error)

      described_class.new(exception, account: 'account-1', context: { source: 'spec' }).capture_exception

      expect(Rails.logger).to have_received(:error).with(
        hash_including(
          error_class: 'StandardError',
          message: 'local failure',
          context: hash_including(source: 'spec', account: 'account-1')
        )
      )
    end
  end
end
