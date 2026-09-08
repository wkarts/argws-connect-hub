require 'rails_helper'

RSpec.describe HubExceptionTracker do
  describe '#capture_exception' do
    it 'logs locally without invoking an external telemetry service' do
      exception = StandardError.new('local failure')
      allow(exception).to receive(:backtrace).and_return(['line 1'])
      allow(Rails.logger).to receive(:error)

      described_class.new(exception, context: { source: 'spec' }).capture_exception

      expect(Rails.logger).to have_received(:error).with(
        hash_including(error_class: 'StandardError', message: 'local failure')
      )
    end
  end
end
