require 'net/imap'
require 'timeout'

class Imap::SentMailAppendService
  SENT_ATTRIBUTE = 'Sent'.freeze
  SENT_FALLBACK_NAMES = ['Sent', 'Sent Items', 'Sent Messages', 'INBOX.Sent', 'Enviados'].freeze
  APPEND_TIMEOUT = 15

  def initialize(channel:, message:)
    @channel = channel
    @message = message
  end

  def perform
    Timeout.timeout(APPEND_TIMEOUT) do
      imap = connect
      begin
        mailbox = sent_mailbox(imap)
        imap.append(mailbox, message.encoded, ['\\Seen'], Time.current)
      ensure
        safely_disconnect(imap)
      end
    end

    true
  end

  private

  attr_reader :channel, :message

  def connect
    imap = Net::IMAP.new(channel.imap_address, port: channel.imap_port, ssl: true)
    imap.login(channel.imap_login, channel.imap_password)
    imap
  end

  def sent_mailbox(imap)
    mailboxes = Array(imap.list('', '*'))

    special_use = mailboxes.find do |mailbox|
      Array(mailbox.attr).any? do |attribute|
        attribute.to_s.delete_prefix('\\').casecmp(SENT_ATTRIBUTE).zero?
      end
    end
    return special_use.name if special_use

    fallback = mailboxes.find do |mailbox|
      SENT_FALLBACK_NAMES.any? { |name| mailbox.name.to_s.casecmp(name).zero? }
    end
    return fallback.name if fallback

    create_sent_mailbox(imap)
  end

  def create_sent_mailbox(imap)
    imap.create('Sent')
    'Sent'
  rescue Net::IMAP::NoResponseError
    raise StandardError, 'Remote IMAP server has no Sent mailbox and refused to create one'
  end

  def safely_disconnect(imap)
    imap.logout unless imap.disconnected?
  rescue StandardError
    nil
  ensure
    begin
      imap.disconnect unless imap.disconnected?
    rescue StandardError
      nil
    end
  end
end
