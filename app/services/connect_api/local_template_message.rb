# frozen_string_literal: true

module ConnectApi
  # Models owned by Connect|API, not templates approved by Meta. This validates
  # the local preview; Connect|API independently renders its persisted version.
  class LocalTemplateMessage
    class Error < StandardError; end

    SOURCE = 'connectapi_local'
    PLACEHOLDER = /\{\{([1-9]\d*)\}\}/
    ORDER = %w[HEADER BODY FOOTER].freeze

    def self.local?(template)
      template.is_a?(Hash) && template['source'] == SOURCE
    end

    def self.available?(template)
      local?(template) && template['status'] == 'LOCAL_READY' &&
        template['execution'] == 'rendered_text' && template['meta_approved'] == false &&
        template['available'] == true && template['enabled'] == true &&
        template['version'].is_a?(Integer) && template['version'].positive?
    end

    def initialize(template, params)
      @template = template
      @params = params
    end

    def payload
      validate_identity!
      components = definition
      body = components.find { |item| item['type'] == 'BODY' }
      values = parameter_values(body['text'])
      {
        name: @template['name'],
        language: { policy: 'deterministic', code: @template['language'] },
        components: [{ type: 'body', parameters: values.map { |value| { type: 'text', text: value } } }],
        connect_api_version: @template['version']
      }
    end

    def rendered_text
      body_values = payload[:components].first[:parameters].map { |item| item[:text] }
      text = definition.map do |component|
        # Block replacement is literal and does not recursively interpret values.
        component['text'].gsub(PLACEHOLDER) { body_values[Regexp.last_match(1).to_i - 1] }
      end.join("\n\n")
      raise Error, 'A mensagem completa excede 4096 caracteres.' if text_length(text) > 4096

      text
    end

    def validate_content!(content)
      raise Error, 'O conteúdo não corresponde ao modelo selecionado. Selecione o modelo novamente.' unless content == rendered_text
    end

    private

    def validate_identity!
      raise Error, 'Modelo local indisponível nesta caixa.' unless self.class.available?(@template)
      unless @params.is_a?(Hash) && @params['name'] == @template['name'] && @params['language'] == @template['language']
        raise Error, 'O modelo selecionado não pertence a esta mensagem.'
      end
      unless @params['connect_api_version'].is_a?(Integer) && @params['connect_api_version'] == @template['version']
        raise Error, 'O modelo foi atualizado. Reconcilie os templates e selecione novamente.'
      end
    end

    def definition
      items = @template['components']
      unless items.is_a?(Array) && items.length.between?(1, 3) && items.all? { |item| item.is_a?(Hash) }
        raise Error, 'Definição do modelo local inválida.'
      end
      types = items.map { |item| item['type'] }
      unless types.uniq == types && (types - ORDER).empty? && types.include?('BODY')
        raise Error, 'Este modelo contém componentes não suportados.'
      end
      items.each do |item|
        type = item['type']
        text = item['text']
        limit = type == 'BODY' ? 4096 : 60
        unless text.is_a?(String) && !text.strip.empty? && text_length(text) <= limit && !text.include?("\0")
          raise Error, 'Texto do modelo local inválido.'
        end
        unless item['format'].nil? || (type == 'HEADER' && item['format'] == 'TEXT')
          raise Error, 'Este modelo contém mídia não suportada.'
        end
        count = variable_count(text)
        raise Error, 'Somente o corpo do modelo pode ter variáveis.' if type != 'BODY' && count.positive?
      end
      items.sort_by { |item| ORDER.index(item['type']) }
    end

    def variable_count(text)
      positions = text.scan(PLACEHOLDER).flatten.map(&:to_i)
      rest = text.gsub(PLACEHOLDER, '')
      count = positions.max || 0
      if rest.include?('{{') || rest.include?('}}') || count > 20 || positions.uniq.sort != (1..count).to_a
        raise Error, 'As variáveis do modelo devem ser posicionais e consecutivas.'
      end
      count
    end

    def parameter_values(text)
      count = variable_count(text)
      values = @params.fetch('processed_params', {})
      unless values.is_a?(Hash) && values.keys.sort == (1..count).map(&:to_s).sort
        raise Error, 'Preencha exatamente as variáveis do modelo selecionado.'
      end
      (1..count).map do |position|
        value = values[position.to_s]
        unless value.is_a?(String) && !value.strip.empty? && text_length(value) <= 1024 && !value.include?("\0")
          raise Error, 'Cada variável deve ser texto não vazio, com até 1024 caracteres.'
        end
        value
      end
    end

    def text_length(value)
      value.encode(Encoding::UTF_16LE).bytesize / 2
    end
  end
end
