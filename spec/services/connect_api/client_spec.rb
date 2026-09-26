require 'rails_helper'
require 'open3'
require 'rbconfig'

describe ConnectApi::Client do
  subject(:client) do
    described_class.new(
      base_url: 'https://connect.example.test',
      api_key: 'instance-secret'
    )
  end

  describe '#request' do
    it 'maps connection reset to a controlled 503 error' do
      allow(HTTParty).to receive(:public_send).and_raise(Errno::ECONNRESET)

      expect { client.list_calls('hub-call-recovery-test') }
        .to raise_error(ConnectApi::Error) do |error|
          expect(error.status).to eq(503)
          expect(error.message).to include('Connect|API indisponível')
        end
    end
  end

  describe 'independent error autoloading' do
    # A fresh process prevents rails_helper or a previous spec from hiding the
    # boot failure by loading Client (and formerly Error as a side effect).
    %w[error_first client_first].each do |order|
      it "autoloads and reloads the error contract with #{order}" do
        script = <<~'RUBY'
          require 'zeitwerk'
          module ConnectApi; end
          loader = Zeitwerk::Loader.new
          loader.push_dir(File.join(ARGV.fetch(0), 'app/services/connect_api'), namespace: ConnectApi)
          loader.enable_reloading
          loader.setup

          if ARGV.fetch(1) == 'client_first'
            ConnectApi::Client
            raise 'Client must not define Error as a side effect' unless ConnectApi.autoload?(:Error)
          end
          error_class = ConnectApi::Error
          if ARGV.fetch(1) == 'error_first'
            raise 'Loading Error must not load Client' unless ConnectApi.autoload?(:Client)
          end
          ConnectApi::Client
          raise 'Error identity changed after Client loaded' unless ConnectApi::Error.equal?(error_class)
          raise 'Incorrect superclass' unless error_class.superclass == StandardError
          error = error_class.new('fixture', status: 503, payload: { 'error' => 'fixture' })
          raise 'Error contract changed' unless error.message == 'fixture' && error.status == 503 && error.payload == { 'error' => 'fixture' }
          plain = error_class.new('plain')
          raise 'Defaults changed' unless plain.status.nil? && plain.payload.nil?

          loader.reload
          reloaded_error = ConnectApi::Error
          raise 'Error was not reloaded' if reloaded_error.equal?(error_class)
          raise 'Reloading Error loaded Client' unless ConnectApi.autoload?(:Client)
          ConnectApi::Client
          raise 'Reloaded identity changed' unless ConnectApi::Error.equal?(reloaded_error)
          loader.unload
        RUBY
        stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-e', script, Rails.root.to_s, order)
        expect(status.success?).to be(true), "#{stdout}\n#{stderr}"
      end
    end
  end
end
