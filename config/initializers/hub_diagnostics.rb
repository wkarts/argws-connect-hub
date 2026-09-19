# frozen_string_literal: true
require Rails.root.join('lib/hub_diagnostics/request_trace')
Rails.application.config.middleware.insert_after(ActionDispatch::RequestId, HubDiagnostics::RequestTrace)
Rails.application.config.filter_parameters += %i[instance_api_key api_key apikey binding_ref hub_binding_ref binding_ticket]

ActiveSupport::Notifications.subscribe('process_action.action_controller') do |_name, started, ended, _id, payload|
  next if payload[:controller].to_s.start_with?('SuperAdmin::Diagnostics')

  params = payload[:params].to_h
  error = payload[:exception_object]
  status = payload[:status].to_i
  level = if status >= 500
            'error'
          elsif status >= 400
            'warn'
          else
            'info'
          end
  attributes = {
    component: 'controller',
    controller: payload[:controller].to_s,
    action: payload[:action].to_s,
    account_id: params['account_id'].to_s.presence,
    http_status: payload[:status],
    duration_ms: ((ended - started) * 1000).round(2)
  }

  if error
    HubDiagnostics::Recorder.error('controller.failed', error, attributes)
  else
    HubDiagnostics::Recorder.emit('controller.completed', attributes.merge(level: level))
  end
end

ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _started, _ended, _id, payload|
  next unless payload[:exception]

  HubDiagnostics::Recorder.emit(
    'database.error',
    level: 'error',
    component: 'postgres',
    exception_class: Array(payload[:exception]).first.to_s
  )
end

if defined?(Sidekiq)
  Sidekiq.configure_server do |config|
    config.error_handlers << proc do |error, context, *_rest|
      job = context[:job].to_h
      HubDiagnostics::Recorder.error(
        'sidekiq.error',
        error,
        component: 'sidekiq',
        job_id: job['jid'],
        job_class: job['class'],
        queue: job['queue']
      )
    end
  end
end
