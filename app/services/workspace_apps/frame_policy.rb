require 'uri'

module WorkspaceApps
  # Conservative evaluation of the anonymous response. Unknown syntax stays
  # inconclusive; absence of a header is never a promise that login will work.
  class FramePolicy
    def initialize(headers:, destination:, parent:)
      @headers = headers
      @destination = URI(destination)
      @parent = URI(parent)
    end

    def call
      policies = directives('content-security-policy')
      report_only = directives('content-security-policy-report-only')
      xfo = Array(@headers['x-frame-options']).join(', ')[0, 2048]
      results = policies.map { |directive| permits?(directive) }
      truncated = policies.any? { |value| value.length >= 2048 } || Array(@headers['content-security-policy']).any? { |value| value.length >= 8192 }
      result = if truncated
                 'inconclusive'
               elsif results.include?(false)
                 'blocked'
               elsif results.include?(nil)
                 'inconclusive'
               elsif policies.any?
                 'no_block_observed'
               else
                 xfo_result(xfo)
               end
      { verdict: result, frame_ancestors: policies, report_only: report_only, x_frame_options: xfo }
    end

    private

    def directives(header)
      Array(@headers[header]).flat_map { |value| value.split(',') }.filter_map do |policy|
        policy.split(';').map(&:strip).find { |directive| directive.match?(/\Aframe-ancestors(?:\s|$)/i) }
      end.map { |value| value[0, 2048] }
    end

    def permits?(directive)
      sources = directive.split(/\s+/)[1..]
      return false if sources.empty? || sources == ["'none'"]

      matches = sources.reject { |source| source == "'none'" }.map { |source| matches_source?(source) }
      return true if matches.include?(true)
      return nil if matches.include?(nil)

      false
    end

    def matches_source?(source)
      return true if source == '*'
      return same_origin?(@destination, @parent) if source == "'self'"
      return scheme_matches?(source.delete_suffix(':')) if %w[http: https:].include?(source.downcase)

      match = source.match(%r{\A(?:(https?)://)?(\*\.)?([a-z0-9.-]+)(?::(\d+|\*))?/?\z}i)
      return nil unless match

      scheme, wildcard, host, port = match.captures
      scheme = (scheme || @destination.scheme).downcase
      port_match = if port.nil?
                     @parent.port == @parent.default_port
                   else
                     port == '*' || @parent.port == port.to_i || (port.to_i == 80 && @parent.port == 443)
                   end
      host_match = wildcard ? @parent.host.downcase.end_with?(".#{host.downcase}") : @parent.host.casecmp?(host)
      host_match && scheme_matches?(scheme) && port_match
    end

    def scheme_matches?(scheme)
      scheme = scheme.downcase
      @parent.scheme == scheme || (scheme == 'http' && @parent.scheme == 'https')
    end

    def same_origin?(a, b)
      a.scheme == b.scheme && a.host.casecmp?(b.host) && a.port == b.port
    end

    def xfo_result(value)
      values = value.split(',').map { |item| item.strip.upcase }.uniq
      return 'no_block_observed' if values.empty?
      return 'blocked' if values.include?('DENY')
      return same_origin?(@destination, @parent) ? 'no_block_observed' : 'blocked' if values == ['SAMEORIGIN']

      'inconclusive'
    end
  end
end
