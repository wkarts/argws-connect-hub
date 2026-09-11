# frozen_string_literal: true

module ConnectApi
  # The existing channel JSONB is a catalog for one inbox, not a global catalog.
  # Remote content is never seeded here. Only HUB administration flags are added.
  class OpeningTemplateCatalog
    class InvalidTemplate < StandardError; end
    class TemplateNotFound < StandardError; end

    LOCAL_KEYS = %w[hub_instance_name hub_opening_enabled hub_remote_present hub_remote_available].freeze

    attr_reader :instance_name

    def initialize(templates, instance_name:)
      @templates = templates.is_a?(Array) ? templates : []
      @instance_name = instance_name.to_s
    end

    def entries
      @templates.select do |template|
        template.is_a?(Hash) && template['hub_instance_name'] == instance_name && !instance_name.empty?
      end
    end

    def available_templates(opening_only: false)
      entries.select do |template|
        template['hub_remote_present'] == true && template['hub_remote_available'] == true &&
          remote_available?(template) && (!opening_only || template['hub_opening_enabled'] == true)
      end
    end

    def find_available(name:, language:, opening_only: false)
      available_templates(opening_only: opening_only).find do |template|
        template['name'] == name && template['language'] == language
      end
    end

    def reconcile(remote_templates)
      raise InvalidTemplate, 'Resposta de templates inválida na Connect|API.' unless remote_templates.is_a?(Array)
      raise InvalidTemplate, 'A caixa não possui uma instância Connect|API definida.' if instance_name.empty?

      previous = entries.to_h { |template| [identity(template), template] }
      imported = remote_templates.map do |remote|
        validate_remote!(remote)
        old = previous[identity(remote)]
        remote.reject { |key, _| LOCAL_KEYS.include?(key) }.merge(
          'hub_instance_name' => instance_name,
          'hub_opening_enabled' => old ? old['hub_opening_enabled'] == true : remote['name'] == 'hello',
          'hub_remote_present' => true,
          'hub_remote_available' => remote_available?(remote)
        )
      end
      # Name + language is the send identity, even when the remote id changes.
      imported = imported.to_h { |template| [identity(template), template] }
      missing = previous.reject { |key, _| imported.key?(key) }.values.map do |template|
        template.merge('hub_remote_present' => false, 'hub_remote_available' => false)
      end
      imported.values + missing
    end

    def set_enabled(name:, language:, enabled:)
      unless enabled == true || enabled == false
        raise ArgumentError, 'Informe enabled como true ou false.'
      end
      unless entries.any? { |template| template['name'] == name && template['language'] == language }
        raise TemplateNotFound, 'Template não encontrado no catálogo desta caixa.'
      end

      entries.map do |template|
        if template['name'] == name && template['language'] == language
          template.merge('hub_opening_enabled' => enabled)
        else
          template
        end
      end
    end

    private

    def identity(template)
      [template['name'], template['language']]
    end

    def validate_remote!(template)
      valid = template.is_a?(Hash) && %w[name language].all? do |key|
        template[key].is_a?(String) && !template[key].strip.empty?
      end
      valid &&= template['components'].is_a?(Array) && template['components'].all? { |component| component.is_a?(Hash) }
      raise InvalidTemplate, 'A Connect|API retornou um template sem nome, idioma ou componentes válidos.' unless valid
    end

    def remote_available?(template)
      status = template['status'].to_s.strip
      (status.empty? || status.casecmp('APPROVED').zero?) &&
        ![false, 0, 'false', '0'].include?(template['available']) &&
        ![false, 0, 'false', '0'].include?(template['enabled'])
    end
  end
end
