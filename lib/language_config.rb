class LanguageConfig
  DEFAULT_LOCALE = 'pt_BR'.freeze
  CONFIG_KEY = 'ENABLED_LANGUAGES'.freeze
  ENV_KEY = 'HUB_ENABLED_LANGUAGES'.freeze

  class << self
    def enabled_codes
      configured = [
        GlobalConfigService.load(CONFIG_KEY, DEFAULT_LOCALE),
        ENV.fetch(ENV_KEY, nil),
        ENV.fetch('DEFAULT_LOCALE', nil)
      ]

      requested = configured.flat_map { |value| normalize(value) }
      ([DEFAULT_LOCALE] + requested).select { |code| supported_codes.include?(code) }.uniq
    rescue StandardError => e
      Rails.logger.warn("Falha ao carregar idiomas habilitados: #{e.message}")
      [DEFAULT_LOCALE]
    end

    def enabled?(locale)
      enabled_codes.include?(locale.to_s)
    end

    def available_locales
      enabled = enabled_codes
      LANGUAGES_CONFIG.values.select { |language| enabled.include?(language[:iso_639_1_code]) }
    end

    def supported_codes
      @supported_codes ||= LANGUAGES_CONFIG.values.map { |language| language[:iso_639_1_code] }.freeze
    end

    private

    def normalize(value)
      values = value.is_a?(Array) ? value : value.to_s.split(/[\s,;]+/)
      values.map(&:to_s).map(&:strip).reject(&:blank?)
    end
  end
end
