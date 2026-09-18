# frozen_string_literal: true
module HubDiagnostics
  class StatusPolicy
    RANK = { 'progress' => 0, 'sent' => 1, 'delivered' => 2, 'read' => 3 }.freeze
    VALID = %w[sent delivered read failed deleted].freeze
    def self.decision(current, incoming)
      return :unknown unless VALID.include?(incoming)
      return :duplicate if current == incoming
      return :stale if incoming == 'failed' && RANK.fetch(current, 0) >= 2
      return :regressive if RANK.key?(current) && RANK.key?(incoming) && RANK[incoming] < RANK[current]
      :apply
    end
  end
end
