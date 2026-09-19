# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'securerandom'
require 'time'

module HubDiagnostics
  # Small shared control file used only by the diagnostics writer threads.
  # Messaging/webhook threads never read this file.
  class CaptureSession
    MINUTES = [15, 30, 60, 120, 240].freeze
    CACHE_TTL = 1.0

    class << self
      def start!(actor_id:, duration_minutes:, channel: nil)
        minutes = Integer(duration_minutes)
        raise ArgumentError, 'Invalid capture duration' unless MINUTES.include?(minutes)

        now = Time.now.utc
        session = {
          'id' => SecureRandom.uuid,
          'started_at' => now.iso8601(6),
          'expires_at' => (now + minutes.minutes).iso8601(6),
          'actor_id' => actor_id,
          'channel_id' => channel&.id,
          'inbox_id' => channel&.inbox&.id,
          'instance_name' => channel&.provider_config.to_h&.dig('instance_name')
        }.compact

        locked do
          FileUtils.mkdir_p(directory, mode: 0o700)
          temporary = "#{path}.#{Process.pid}.tmp"
          File.open(temporary, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |io|
            io.write(JSON.generate(session))
            io.flush
            io.fsync
          end
          File.rename(temporary, path)
        ensure
          File.unlink(temporary) if defined?(temporary) && File.exist?(temporary)
        end

        invalidate_cache!
        session
      end

      def stop!
        locked { File.unlink(path) if File.file?(path) && !File.symlink?(path) }
        invalidate_cache!
        true
      rescue StandardError
        false
      end

      def current
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if @cache_pid == Process.pid && @cache_checked_at && now - @cache_checked_at < CACHE_TTL
          return @cached_session
        end

        @cache_pid = Process.pid
        @cache_checked_at = now
        @cached_session = read_current
      rescue StandardError
        @cached_session = nil
      end

      def active?
        current.present?
      end

      private

      def read_current
        return unless File.file?(path)
        return if File.symlink?(path)

        data = JSON.parse(File.read(path, mode: 'r:UTF-8'))
        expires_at = Time.iso8601(data.fetch('expires_at'))
        return if expires_at <= Time.now.utc

        data
      rescue JSON::ParserError, ArgumentError, KeyError
        nil
      end

      def directory
        File.expand_path(ENV.fetch('HUB_DIAGNOSTICS_DIR', Rails.root.join('log/hub_diagnostics').to_s))
      end

      def path
        File.join(directory, '.capture-session.json')
      end

      def lock_path
        File.join(directory, '.capture-session.lock')
      end

      def locked
        FileUtils.mkdir_p(directory, mode: 0o700)
        File.open(lock_path, File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        ensure
          lock.flock(File::LOCK_UN) if lock
        end
      end

      def invalidate_cache!
        @cache_pid = nil
        @cache_checked_at = nil
        @cached_session = nil
      end
    end
  end
end
