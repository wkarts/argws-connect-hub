# frozen_string_literal: true

module ConnectApi
  # Builds a Graph-compatible request from the current catalog, never from
  # client-supplied message text or a server-wide credential.
  class LocalTemplateDelivery
    class Error < StandardError; end

    def initialize(catalog:, message:, template_info:)
      @catalog = catalog
      @message = message
      @template_info = template_info
    end

    def payload
      entry = @catalog.find_available(name: @template_info[:name], language: @template_info[:lang_code])
      raise Error, 'O modelo não está disponível. Atualize o catálogo desta caixa.' unless entry
      return nil unless entry['origin'] == 'CONNECT_LOCAL'

      params = @message.additional_attributes.to_h['template_params']
      unless params.is_a?(Hash) && params['connect_template_id'] == entry['id'] &&
             params['connect_template_revision'].is_a?(Integer) && params['connect_template_revision'] == entry['revision']
        raise Error, 'O modelo foi alterado. Atualize o catálogo e selecione-o novamente.'
      end

      body = body_text(entry)
      values = params['processed_params'] || {}
      keys = body.scan(/{{([1-9]\d*)}}/).flatten.uniq.sort_by(&:to_i)
      unless values.is_a?(Hash) && values.keys.sort == keys.sort &&
             values.values.all? { |value| value.is_a?(String) && !value.strip.empty? }
        raise Error, 'Preencha exatamente as variáveis de texto deste modelo.'
      end
      rendered = body.gsub(/{{([1-9]\d*)}}/) { values.fetch(Regexp.last_match(1)) }
      if rendered != @message.content
        raise Error, 'A prévia não corresponde ao modelo selecionado. Selecione o modelo novamente.'
      end

      {
        name: entry['name'],
        language: { code: entry['language'] },
        components: [{ type: 'body', parameters: keys.map { |key| { type: 'text', text: values.fetch(key) } } }],
        connect_template_id: entry['id'],
        connect_template_revision: entry['revision']
      }
    end

    private

    def body_text(entry)
      components = entry['components']
      unless components.is_a?(Array) && components.length == 1 && components[0]['type'] == 'BODY' &&
             components[0]['text'].is_a?(String)
        raise Error, 'Este modelo local não possui um corpo de texto suportado.'
      end

      components[0]['text']
    end
  end
end
