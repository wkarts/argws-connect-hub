# frozen_string_literal: true

require 'net/imap'
require 'timeout'

# Mirrors a message that was successfully delivered by SMTP into the physical
# Sent mailbox of a generic IMAP account. The remote mailbox remains the source
# of truth; HUB does not treat this append as authoritative local storage.
class Imap::SentMailAppendService
  SENT_MAILBOX_CANDIDATES = ['Sent', 'Sent Items', 'Sent Messages', 'INBOX.Sent', 'Enviados'].freeze
  TIMEOUT_SECONDS = 15

  def initialize(channel:, message:)
    @channel = channel
    @message = message
  end

  def perform
    Timeout.timeout(TIMEOUT_SECONDS) do
      client = build_client
      begin
        mailbox = resolve_sent_mailbox(client)
        client.append(mailbox, message.encoded, [:Seen], Time.current)
      ensure
        terminate(client)
      end
    end
    true
  end

  private

  attr_reader :channel, :message

  def build_client
    port = channel.imap_port.to_i
    port = channel.imap_enable_ssl ? 993 : 143 unless port.positive?

    client = Net::IMAP.new(channel.imap_address, port: port, ssl: channel.imap_enable_ssl)
    authenticate(client)
    client
  end

  def authenticate(client)
    client.authenticate('PLAIN', channel.imap_login, channel.imap_password)
  rescue Net::IMAP::NoResponseError, Net::IMAP::BadResponseError
    # Some generic servers advertise LOGIN but not SASL PLAIN.
    client.login(channel.imap_login, channel.imap_password)
  end

  def resolve_sent_mailbox(client)
    mailboxes = Array(client.list('', '*'))
    special = mailboxes.find do |entry|
      Array(entry.attr).any? { |attr| attr.to_s.delete_prefix('\\').casecmp('sent').zero? }
    end
    return special.name if special&.name.present?

    names = mailboxes.map(&:name)
    candidate = SENT_MAILBOX_CANDIDATES.find { |name| names.any? { |existing| existing.casecmp(name).zero? } }
    return names.find { |existing| existing.casecmp(candidate).zero? } if candidate

    client.create('Sent')
    'Sent'
  rescue Net::IMAP::NoResponseError
    # If folder discovery/creation is restricted, use the conventional name and
    # let APPEND return the server-specific error to the observer logger.
    'Sent'
  end

  def terminate(client)
    client.logout unless client.disconnected?
  rescue Net::IMAP::Error, IOError
    client.disconnect unless client.disconnected?
  end
end
