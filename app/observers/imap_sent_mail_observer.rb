# frozen_string_literal: true

# Receives ActionMailer delivery notifications and mirrors generic IMAP/SMTP
# messages to the physical remote Sent mailbox. Failures here must never turn a
# successful SMTP delivery into a failed HUB message.
class ImapSentMailObserver
  def self.delivered_email(message)
    inbox_id = message.instance_variable_get(:@hub_inbox_id)
    return if inbox_id.blank?

    inbox = Inbox.find_by(id: inbox_id)
    channel = inbox&.channel
    return unless channel.is_a?(Channel::Email)
    return unless channel.imap_enabled? && channel.smtp_enabled?

    # Google and Microsoft already maintain their own Sent mailbox server-side.
    return if channel.google? || channel.microsoft?

    Imap::SentMailAppendService.new(channel: channel, message: message).perform
  rescue StandardError => e
    Rails.logger.warn("[HUB][IMAP][Sent] append failed: #{e.class}: #{e.message}")
  end
end
