# frozen_string_literal: true

# Initializers run before Zeitwerk necessarily resolves custom observer paths.
# Load the observer explicitly so assets:precompile and application boot never
# fail with an uninitialized constant.
require Rails.root.join('app/observers/imap_sent_mail_observer').to_s

Mail.register_observer(ImapSentMailObserver)
