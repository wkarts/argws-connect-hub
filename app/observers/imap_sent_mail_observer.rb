# frozen_string_literal: true

require 'net/imap'

# Mirrors successfully delivered SMTP messages to the remote IMAP Sent mailbox.
# The remote mailbox remains the physical source of truth.
class ImapSentMailObserver
  SENT_CANDIDATES = ['Sent', 'Sent Messages', 'Sent Items', 'INBOX.Sent'].freeze

  def self.delivered_email(message)
    from = Array(message.from).first.to_s.downcase
    return if from.blank?

    channel = Channel::Email.find_by('LOWER(email) = ?', from)
    return unless channel&.imap_enabled? && channel&.smtp_enabled?
    return if channel.google? || channel.microsoft? # Providers already maintain Sent themselves.

    append(channel, message.encoded)
  rescue StandardError => e
    Rails.logger.warn("[HUB IMAP SENT] #{e.class}: #{e.message}")
  end

  def self.append(channel, raw_message)
    imap = Net::IMAP.new(channel.imap_address, port: channel.imap_port, ssl: channel.imap_enable_ssl)
    authenticate(imap, channel)
    mailbox = sent_mailbox(imap)
    imap.append(mailbox, raw_message, [:Seen], Time.current)
  ensure
    begin
      imap&.logout
    rescue StandardError
      imap&.disconnect unless imap&.disconnected?
    end
  end


  def self.authenticate(imap, channel)
    imap.authenticate('PLAIN', channel.imap_login, channel.imap_password)
  rescue Net::IMAP::NoResponseError, Net::IMAP::BadResponseError
    # Some generic IMAP servers advertise LOGIN but not SASL PLAIN.
    imap.login(channel.imap_login, channel.imap_password)
  end

  def self.sent_mailbox(imap)
    boxes = Array(imap.list('', '*'))
    special = boxes.find { |box| Array(box.attr).map(&:to_s).any? { |a| a.casecmp('Sent').zero? || a.casecmp('\\Sent').zero? } }
    return special.name if special

    names = boxes.map(&:name)
    SENT_CANDIDATES.find { |candidate| names.include?(candidate) } || begin
      imap.create('Sent') unless names.include?('Sent')
      'Sent'
    end
  end
end
