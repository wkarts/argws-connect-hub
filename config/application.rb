# frozen_string_literal: true

require_relative 'boot'

require 'rails/all'

Bundler.require(*Rails.groups)

module Hub
  class Application < Rails::Application
    config.load_defaults 7.0

    config.eager_load_paths << Rails.root.join('lib')
    config.generators.javascripts = false
    config.generators.stylesheets = false

    config.x = config_for(:app).with_indifferent_access

    config.active_record.yaml_column_permitted_classes = [ActiveSupport::HashWithIndifferentAccess]

    config.action_dispatch.default_headers = {
      'X-Frame-Options' => 'ALLOWALL'
    }
  end

  def self.config
    @config ||= Rails.configuration.x
  end

  def self.version
    env_version = ENV.fetch('HUB_BUILD_VERSION', '').to_s.strip
    return env_version if env_version.present?

    [Rails.root.join('.hub_version'), Rails.root.join('VERSION')].each do |path|
      next unless File.file?(path)

      file_version = File.read(path).to_s.strip
      return file_version if file_version.present?
    end

    config[:version].presence || 'desconhecida'
  end

  def self.redis_ssl_verify_mode
    ENV['REDIS_OPENSSL_VERIFY_MODE'] == 'none' ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
  end
end
