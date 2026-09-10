# frozen_string_literal: true

require 'pathname'

module HubApp
  def self.root
    Pathname.new(File.expand_path('..', __dir__))
  end

  def self.max_limit
    100_000
  end

  # HUB 1.x é distribuído e executado sempre como edição Enterprise.
  # A disponibilidade dos recursos continua sendo controlada pelas feature flags
  # de cada conta; não existe downgrade de edição por variável de ambiente.
  def self.enterprise?
    true
  end

  def self.custom?
    @custom ||= root.join('custom').exist?
  end

  def self.help_center_root
    ENV.fetch('HELPCENTER_URL', nil) || ENV.fetch('FRONTEND_URL', nil)
  end

  def self.extensions
    custom? ? %w[enterprise custom] : %w[enterprise]
  end
end
