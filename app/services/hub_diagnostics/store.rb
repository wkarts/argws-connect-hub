# frozen_string_literal: true
require 'json'
require 'fileutils'
require 'securerandom'
require 'time'

module HubDiagnostics
  class Store
    DEFAULT_FILE_BYTES = 8 * 1024 * 1024

    attr_reader :directory, :file_bytes, :file_count, :retention_seconds

    def initialize(directory:, file_bytes: DEFAULT_FILE_BYTES, file_count: 8, retention_seconds: 259_200)
      @directory = File.expand_path(directory.to_s)
      @file_bytes = [[Integer(file_bytes), 4096].max, 64 * 1024 * 1024].min
      @file_count = [[Integer(file_count), 2].max, 32].min
      @retention_seconds = [[Integer(retention_seconds), 3600].max, 30 * 86_400].min
      FileUtils.mkdir_p(@directory)
    end

    def append(attributes)
      record = Sanitizer.call(attributes).merge(
        'event_id' => SecureRandom.uuid,
        'timestamp' => Time.now.utc.iso8601(6)
      )
      line = JSON.generate(record) + "
"
      line = JSON.generate(record.slice('event_id', 'timestamp', 'event', 'component', 'level', 'trace_id').merge('truncated' => true)) + "
" if line.bytesize > 32_768

      with_lock do
        rotate if File.exist?(active_path) && File.size(active_path) + line.bytesize > file_bytes
        File.open(active_path, 'a', 0o600) { |io| io.write(line) }
      end
      record
    end

    def each_record
      return enum_for(__method__) unless block_given?

      cutoff = Time.now.utc - retention_seconds
      snapshot_paths.each do |name|
        File.foreach(name) do |line|
          next if line.bytesize > 65_536
          begin
            record = JSON.parse(line)
            next if Time.iso8601(record.fetch('timestamp')) < cutoff
          rescue JSON::ParserError, ArgumentError, KeyError
            next
          end
          yield record
        end
      end
    end

    def matching(filters = {})
      return enum_for(__method__, filters) unless block_given?

      since_time = filters['since'].present? ? Time.iso8601(filters['since']) : nil
      until_time = filters['until'].present? ? Time.iso8601(filters['until']) : nil
      exact = filters.reject { |key, value| %w[since until].include?(key) || value.to_s.empty? }

      each_record do |record|
        timestamp = Time.iso8601(record['timestamp'])
        next if since_time && timestamp < since_time
        next if until_time && timestamp >= until_time
        next unless exact.all? { |key, value| record[key].to_s == value.to_s }

        yield record
      end
    end

    def find(event_id)
      return unless event_id.to_s.match?(/A[0-9a-f-]{36}z/i)

      each_record.find { |record| record['event_id'] == event_id }
    end

    def health
      files = snapshot_paths
      {
        files: files.length,
        bytes: files.sum { |name| File.size(name) },
        max_bytes: file_bytes * file_count,
        retention_seconds: retention_seconds,
        writable: File.writable?(directory),
        shared_volume_required: true
      }
    end

    private

    def active_path
      File.join(directory, 'events.jsonl')
    end

    def rotated_path(index)
      File.join(directory, "events.#{index}.jsonl")
    end

    def snapshot_paths
      ([active_path] + (1...file_count).map { |index| rotated_path(index) })
        .select { |name| File.file?(name) }
        .reverse
    end

    def lock_path
      File.join(directory, '.events.lock')
    end

    def with_lock
      File.open(lock_path, 'a') do |lock|
        lock.flock(File::LOCK_EX)
        yield
      ensure
        lock.flock(File::LOCK_UN) if lock
      end
    end

    def rotate
      (file_count - 1).downto(2) do |index|
        previous = rotated_path(index - 1)
        File.rename(previous, rotated_path(index)) if File.exist?(previous)
      end
      File.rename(active_path, rotated_path(1)) if File.exist?(active_path)
    end
  end
end
