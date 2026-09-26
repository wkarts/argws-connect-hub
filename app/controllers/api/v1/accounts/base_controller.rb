class Api::V1::Accounts::BaseController < Api::BaseController
  include SwitchLocale
  include EnsureCurrentAccountHelper
  before_action :current_account
  after_action :issue_group_media_session

  def issue_group_media_session
    Whatsapp::Groups::MediaSession.issue(self)
  end
  private :issue_group_media_session
  around_action :switch_locale_using_account_locale
end
