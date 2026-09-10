require 'rails_helper'

RSpec.describe LanguageConfig do
  describe '.enabled_codes' do
    it 'keeps only pt-BR enabled by default' do
      allow(GlobalConfigService).to receive(:load)
        .with('ENABLED_LANGUAGES', 'pt_BR')
        .and_return('pt_BR')

      with_modified_env HUB_ENABLED_LANGUAGES: '', DEFAULT_LOCALE: '' do
        expect(described_class.enabled_codes).to eq(['pt_BR'])
      end
    end

    it 'allows additional languages through the administrative configuration' do
      allow(GlobalConfigService).to receive(:load)
        .with('ENABLED_LANGUAGES', 'pt_BR')
        .and_return('pt_BR,en')

      with_modified_env HUB_ENABLED_LANGUAGES: '', DEFAULT_LOCALE: '' do
        expect(described_class.enabled_codes).to contain_exactly('pt_BR', 'en')
      end
    end

    it 'allows additional languages through environment configuration' do
      allow(GlobalConfigService).to receive(:load)
        .with('ENABLED_LANGUAGES', 'pt_BR')
        .and_return('pt_BR')

      with_modified_env HUB_ENABLED_LANGUAGES: 'es', DEFAULT_LOCALE: '' do
        expect(described_class.enabled_codes).to contain_exactly('pt_BR', 'es')
      end
    end

    it 'ignores unknown locale codes' do
      allow(GlobalConfigService).to receive(:load)
        .with('ENABLED_LANGUAGES', 'pt_BR')
        .and_return('pt_BR,xx')

      with_modified_env HUB_ENABLED_LANGUAGES: '', DEFAULT_LOCALE: '' do
        expect(described_class.enabled_codes).to eq(['pt_BR'])
      end
    end
  end
end
