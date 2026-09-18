# frozen_string_literal: true
require 'json'
require 'fileutils'
require 'securerandom'
require 'time'
require_relative 'sanitizer'
module HubDiagnostics
  class Store
    DEFAULT_FILE_BYTES = 8 * 1024 * 1024
    attr_reader :directory, :file_bytes, :file_count, :retention_seconds
    def initialize(directory:, file_bytes: DEFAULT_FILE_BYTES, file_count: 8, retention_seconds: 259_200)
      @directory = File.expand_path(directory.to_s)
      @file_bytes = [[Integer(file_bytes), 4096].max, 64 * 1024 * 1024].min
      @file_count = [[Integer(file_count), 2].max, 32].min
      @retention_seconds = [[Integer(retention_seconds), 3600].max, 30 * 86_400].min
      FileUtils.mkdir_p(@directory, mode: 0o700)
      raise IOError, 'Diagnostics directory cannot be a symlink' if File.symlink?(@directory)
    end
    def append(attributes)
      record = Sanitizer.call(attributes).merge(
        'event_id' => SecureRandom.uuid, 'timestamp' => Time.now.utc.iso8601(6)
      )
      line = JSON.generate(record) + "\n"
      if line.bytesize > 32_768
        record.delete('backtrace'); record.delete('details'); record['truncated'] = true
        line = JSON.generate(record) + "\n"
      end
      if line.bytesize > file_bytes
        record = record.slice('event_id', 'timestamp', 'event', 'component', 'level', 'trace_id').transform_values { |value| value.is_a?(String) ? value.slice(0, 256) : value }.merge('truncated' => true, 'reason' => 'record_size_limit')
        line = JSON.generate(record) + "\n"
      end
      locked do
        purge_expired
        rotate if File.exist?(path) && File.size(path) + line.bytesize > file_bytes
        flags = File::WRONLY | File::CREAT | File::APPEND | File::NOFOLLOW
        File.open(path, flags, 0o600) { |io| io.write(line) }
      end
      record
    end
    # Open bounded inode snapshots while locked, read outside the writer's lock.
    # This also works when a different Rails/Sidekiq process rotates the files.
    def each_record
      return enum_for(__method__) unless block_given?
      snapshots = []
      locked do
        paths.reverse_each do |name|
          next unless File.file?(name) && !File.symlink?(name)
          io = File.open(name, File::RDONLY | File::NOFOLLOW)
          snapshots << [io, io.stat.size]
        end
      end
      cutoff = Time.now.utc - retention_seconds
      snapshots.each do |io, bytes|
        while io.pos < bytes && (line = io.gets(65_536))
          next unless line.end_with?("\n")
          begin
            record = JSON.parse(line)
            next if Time.iso8601(record.fetch('timestamp')) < cutoff
          rescue JSON::ParserError, ArgumentError, KeyError
            next
          end
          yield record
        end
      end
    ensure
      snapshots&.each { |io, _bytes| io.close unless io.closed? }
    end
    def matching(filters = {})
      return enum_for(__method__, filters) unless block_given?
      since = filters['since'] && Time.iso8601(filters['since'])
      until_time = filters['until'] && Time.iso8601(filters['until'])
      exact = filters.reject { |key, val| %w[since until].include?(key) || val.to_s.empty? }
      each_record do |record|
        timestamp = Time.iso8601(record['timestamp'])
        next if since && timestamp < since
        next if until_time && timestamp >= until_time
        next unless exact.all? { |key, value| record[key].to_s == value.to_s }
        yield record
      end
    end
    def find(event_id)
      return unless event_id.to_s.match?(/\A[0-9a-f-]{36}\z/i)
      each_record.find { |record| record['event_id'] == event_id }
    end
    def health
      locked do
      files = paths.select { |name| File.file?(name) && !File.symlink?(name) }
      { files: files.length, bytes: files.sum { |name| File.size(name) },
        max_bytes: file_bytes * file_count, retention_seconds: retention_seconds,
        writable: File.writable?(directory), shared_volume_required: true }
      end
    end
    private
    def path(index = 0)
      File.join(directory, index.zero? ? 'events.jsonl' : "events.#{index}.jsonl")
    end
    def paths
      (0...file_count).map { |index| path(index) }
    end
    def locked
      lock_path = File.join(directory, '.events.lock')
      File.open(lock_path, File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      ensure
        lock.flock(File::LOCK_UN) if lock
      end
    end
    def rotate
      (file_count - 1).downto(1) do |index|
        File.rename(path(index - 1), path(index)) if File.exist?(path(index - 1))
      end
    end
    def purge_expired
      paths.each do |name|
        File.unlink(name) if File.file?(name) && File.mtime(name) < Time.now - retention_seconds
      end
    end
  end
end
