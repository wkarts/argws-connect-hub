# frozen_string_literal: true
require 'json'
module HubDiagnostics
  class EventSplitter
    MAX_EVENTS = 1000
    def self.call(payload)
      data = JSON.parse(JSON.generate(payload))
      result = []
      Array(data['entry']).each do |entry|
        next unless entry.is_a?(Hash)
        Array(entry['changes']).each do |change|
          next unless change.is_a?(Hash) && change['value'].is_a?(Hash)
          value = change['value']
          %w[messages statuses].each do |kind|
            Array(value[kind]).each do |item|
              next unless item.is_a?(Hash)
              raise ArgumentError, 'Webhook event limit exceeded' if result.size >= MAX_EVENTS
              single = value.reject { |key, _| %w[messages statuses].include?(key) }.merge(kind => [item])
              if kind == 'messages' && Array(single['contacts']).size > 1
                contact = single['contacts'].find { |row| row.is_a?(Hash) && row['wa_id'].to_s == item['from'].to_s }
                single['contacts'] = contact ? [contact] : []
              end
              result << { 'object' => data['object'], 'entry' => [
                entry.merge('changes' => [change.merge('value' => single)])
              ] }
            end
          end
        end
      end
      result
    end
  end
end
