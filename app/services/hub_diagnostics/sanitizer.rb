# frozen_string_literal: true
require 'json'
module HubDiagnostics
  # Diagnostics never receives raw requests, headers, message bodies or job arguments.
  class Sanitizer
    SAFE_KEYS = %w[event_id timestamp level event component request_id trace_id account_id inbox_id
                   channel_id conversation_id message_id source_id job_id job_class queue attempt
                   duration_ms http_status status previous_status reason exception_class backtrace
                   instance_name operation_id binding_id actor_id count details from_me offset page
                   records_examined records_processed has_more truncated version environment result
                   provider_timestamp parent_event_id enabled].freeze
    SECRET = /password|passwd|secret|token|api.?key|authorization|cookie|credential|signature|hub_binding_ref/i
    def self.call(value, depth = 0)
      return '[DEPTH_LIMIT]' if depth > 6
      case value
      when Hash
        value.each_with_object({}) do |(key, item), result|
          name = key.to_s
          next unless SAFE_KEYS.include?(name)
          result[name] = name.match?(SECRET) ? '[FILTERED]' : call(item, depth + 1)
        end
      when Array then value.first(30).map { |item| call(item, depth + 1) }
      when String
        value.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
             .gsub(/[\r\n\x00-\x08\x0b\x0c\x0e-\x1f]/, ' ')
             .gsub(%r{https?://[^\s]+}, '[URL_FILTERED]').slice(0, 1000)
      when Numeric, TrueClass, FalseClass, NilClass then value
      else value.class.name
      end
    end
  end
end
