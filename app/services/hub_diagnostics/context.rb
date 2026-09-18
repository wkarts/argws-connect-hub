# frozen_string_literal: true
class HubDiagnostics::Context < ActiveSupport::CurrentAttributes
  attribute :trace_id, :request_id, :binding_snapshot
end
