# frozen_string_literal: true

require 'cgi'
require 'uri'

class Whatsapp::ConnectApiTemplateSyncService
  class Error < StandardError; end

  MAX_PAGES = 100

  def initialize(channel)
    @channel = channel
  end

  def sync!
    started_at = Time.current
    identity = channel_identity
    templates = fetch_templates

    @channel.with_lock do
      raise Error, 'A instância da caixa mudou durante a sincronização. Reconcilie novamente.' unless channel_identity == identity
      # An older, slower request must not overwrite a newer completed sync.
      return @channel.message_templates if @channel.message_templates_last_updated && @channel.message_templates_last_updated > started_at

      persist!(catalog.reconcile(templates), message_templates_last_updated: Time.current)
    end
    @channel.message_templates
  rescue ConnectApi::OpeningTemplateCatalog::InvalidTemplate => e
    raise Error, e.message
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    raise Error, 'Tempo esgotado ao consultar os templates da Connect|API. O catálogo anterior foi preservado.'
  rescue JSON::ParserError
    raise Error, 'Resposta de templates inválida na Connect|API. O catálogo anterior foi preservado.'
  rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH
    raise Error, 'Não foi possível consultar os templates da Connect|API. O catálogo anterior foi preservado.'
  end

  def set_enabled!(name:, language:, enabled:)
    @channel.with_lock do
      persist!(catalog.set_enabled(name: name, language: language, enabled: enabled))
    end
  end

  private

  def catalog
    @channel.opening_template_catalog
  end

  def channel_identity
    @channel.provider_config.to_h.values_at('instance_name', 'business_account_id', 'url', 'api_key')
  end

  def persist!(templates, **attributes)
    # Saving/validating the channel here would provision webhooks again. Both
    # reconciliation and administration merge only these JSONB fields under lock.
    @channel.update_columns( # rubocop:disable Rails/SkipsModelValidations
      { message_templates: templates, updated_at: Time.current }.merge(attributes)
    )
    @channel.inbox&.touch
  end

  def fetch_templates
    url = templates_url
    first_uri = URI.parse(url)
    headers = @channel.provider_service.api_headers
    templates = []
    visited = {}

    while url
      raise Error, 'Paginação inválida ou excessiva nos templates da Connect|API.' if visited[url] || visited.size >= MAX_PAGES

      visited[url] = true
      response = HTTParty.get(url, headers: headers, timeout: request_timeout, follow_redirects: false)
      unless response.success?
        raise Error, "Falha ao consultar templates da Connect|API (HTTP #{response.code}). O catálogo anterior foi preservado."
      end

      payload = response.parsed_response
      unless payload.is_a?(Hash) && payload['data'].is_a?(Array) && !payload.key?('error')
        raise Error, 'Resposta de templates inválida na Connect|API. O catálogo anterior foi preservado.'
      end

      templates.concat(payload['data'])
      paging = payload['paging']
      raise Error, 'Paginação de templates inválida na Connect|API.' unless paging.nil? || paging.is_a?(Hash)

      url = next_page_url(paging && paging['next'], first_uri)
    end
    templates
  end

  def templates_url
    config = @channel.provider_config.to_h
    base = config['url'].to_s.sub(%r{/+$}, '')
    business_id = config['business_account_id'].to_s
    uri = URI.parse(base)
    unless %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && business_id.present?
      raise Error, 'Reconcilie a configuração da caixa antes de sincronizar os templates.'
    end

    "#{base}/v14.0/#{CGI.escape(business_id)}/message_templates"
  rescue URI::InvalidURIError
    raise Error, 'Endereço da Connect|API inválido na configuração desta caixa.'
  end

  def next_page_url(value, first_uri)
    return nil if value.blank?
    raise Error, 'Paginação de templates inválida na Connect|API.' unless value.is_a?(String)

    uri = URI.join(first_uri.to_s, value)
    unless [uri.scheme, uri.host, uri.port, uri.path] == [first_uri.scheme, first_uri.host, first_uri.port, first_uri.path] && uri.userinfo.nil?
      raise Error, 'A Connect|API retornou uma paginação fora do catálogo desta instância.'
    end

    # Never forward credentials to another host/resource or accept a token from
    # a pagination link; every page uses this inbox's instance Authorization.
    query = URI.decode_www_form(uri.query.to_s).reject { |key, _| %w[access_token apikey].include?(key.downcase) }
    uri.query = query.empty? ? nil : URI.encode_www_form(query)
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError, ArgumentError
    raise Error, 'Paginação de templates inválida na Connect|API.'
  end

  def request_timeout
    value = GlobalConfigService.load('CONNECT_API_REQUEST_TIMEOUT', ENV.fetch('CONNECT_API_REQUEST_TIMEOUT', 60)).to_i
    value.positive? ? value : 60
  end
end
