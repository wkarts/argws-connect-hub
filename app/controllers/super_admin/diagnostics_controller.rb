# frozen_string_literal: true
require 'zlib'
require 'tempfile'
require 'digest'
class SuperAdmin::DiagnosticsController < SuperAdmin::ApplicationController
  helper HubAdminUiHelper
  before_action :private_response!
  FILTERS = %w[since until account_id inbox_id channel_id conversation_id message_id source_id trace_id level event operation_id].freeze
  EXPORT_LIMIT = 50_000
  def show
    @filters = validated_filters
    @health = HubDiagnostics::Recorder.store.health
    @events = []
    HubDiagnostics::Recorder.store.matching(@filters).each do |event|
      @events << event
      @events.shift if @events.length > 200
    end
    @events.reverse!
    @channels = Channel::Whatsapp.where(provider: 'connectapi').includes(:inbox).order(:id)
  rescue ArgumentError => error
    render plain: "Filtros inválidos: #{error.class.name}", status: :unprocessable_entity
  end
  def download
    filters = validated_filters
    file = Tempfile.new(['hub-diagnostics-', '.jsonl.gz'])
    # Gzip writes arbitrary binary bytes (including 0x8B). Keep the tempfile in
    # binary mode so Ruby never attempts an ASCII-8BIT -> UTF-8 conversion.
    file.binmode
    count = 0
    export_bytes = 0
    truncated = false
    digest = Digest::SHA256.new
    gzip = Zlib::GzipWriter.new(file)
    gzip.write(JSON.generate({ kind: 'manifest', schema: 'hub-diagnostics/1', generated_at: Time.now.utc.iso8601,
                               timezone: 'UTC', display_timezone: 'America/Bahia', filters: filters,
                               environment: Rails.env, rails_version: Rails.version, ruby_version: RUBY_VERSION,
                               application_version: (Hub.version if defined?(Hub)),
                               build_sha: ENV['APP_REVISION'].to_s.first(64),
                               coverage: 'Instrumented HUB events; not raw Docker/Connect API/server logs',
                               retention: HubDiagnostics::Recorder.store.health,
                               redacted: true, max_records: EXPORT_LIMIT }) + "
")
    HubDiagnostics::Recorder.store.matching(filters).each do |event|
      if count >= EXPORT_LIMIT
        truncated = true
        break
      end
      line = JSON.generate(event) + "
"
      if export_bytes + line.bytesize > 16.megabytes
        truncated = true
        break
      end
      export_bytes += line.bytesize
      digest.update(line)
      gzip.write(line)
      count += 1
    end
    gzip.write(JSON.generate({ kind: 'summary', records: count, truncated: truncated,
                               sha256_event_lines: digest.hexdigest }) + "
")
    gzip.finish
    file.flush
    payload = File.binread(file.path)
    HubDiagnostics::Recorder.emit('diagnostics.exported', actor_id: current_super_admin.id, count: count, truncated: truncated)
    send_data payload, filename: "hub-diagnostico-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.jsonl.gz",
                        type: 'application/gzip', disposition: 'attachment'
  rescue ArgumentError
    render plain: 'Período ou filtros inválidos.', status: :unprocessable_entity
  ensure
    file&.close!
  end
  def replay_status
    event = HubDiagnostics::Recorder.store.find(params[:event_id])
    unless event && %w[status.received status.deferred status.orphaned].include?(event['event'])
      return render plain: 'Evento não encontrado, expirado ou não reprocessável.', status: :unprocessable_entity
    end
    HubDiagnostics::ReplayStatusJob.perform_later(event['event_id'], current_super_admin.id)
    redirect_to super_admin_diagnostics_path, notice: 'Reprocessamento do status enfileirado. Nenhuma mensagem será reenviada.'
  end
  def sync_messages
    unless ENV['HUB_CONNECT_RELIABILITY_ENABLED'] == 'true'
      return render plain: 'Habilite HUB_CONNECT_RELIABILITY_ENABLED após homologação.', status: :forbidden
    end
    channel = Channel::Whatsapp.find_by!(id: params[:channel_id], provider: 'connectapi')
    minutes = Integer(params[:minutes].to_s, 10)
    raise ArgumentError unless (1..120).cover?(minutes)
    operation_id = SecureRandom.uuid
    Channels::Whatsapp::ConnectApiDiagnosticSyncJob.perform_later(channel.id, minutes, operation_id, current_super_admin.id)
    redirect_to super_admin_diagnostics_path(operation_id: operation_id), notice: 'Reconciliação enfileirada. Ela importa registros existentes, sem enviar mensagens.'
  rescue ArgumentError
    render plain: 'Informe entre 1 e 120 minutos.', status: :unprocessable_entity
  end
  private
  def private_response!
    response.headers['Cache-Control'] = 'no-store, private'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end
  def validated_filters
    filters = params.permit(*FILTERS).to_h.reject { |_key, value| value.blank? }
    filters.each do |key, value|
      raise ArgumentError if value.to_s.length > 160
      if %w[since until].include?(key)
        parsed = value.match?(/(?:Z|[+-]\d{2}:\d{2})\z/) ? Time.iso8601(value) : ActiveSupport::TimeZone['America/Bahia'].parse(value)
        raise ArgumentError unless parsed
        filters[key] = parsed.utc.iso8601
      end
    end
    filters['since'] ||= 24.hours.ago.utc.iso8601
    filters['until'] ||= Time.now.utc.iso8601
    raise ArgumentError unless Time.iso8601(filters['until']) > Time.iso8601(filters['since'])
    filters
  end
end
