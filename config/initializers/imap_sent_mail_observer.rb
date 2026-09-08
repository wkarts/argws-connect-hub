# The observer is required explicitly because initializers run before Zeitwerk
# can safely resolve every application constant during assets:precompile.
require Rails.root.join('app/observers/imap_sent_mail_observer')

ActionMailer::Base.register_observer(ImapSentMailObserver)
