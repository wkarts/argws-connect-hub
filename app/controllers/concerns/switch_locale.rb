module SwitchLocale
  extend ActiveSupport::Concern

  private

  def switch_locale(&)
    locale ||= locale_from_params
    locale ||= locale_from_custom_domain
    locale ||= locale_from_env_variable
    set_locale(locale, &)
  end

  def switch_locale_using_account_locale(&)
    locale = locale_from_account(@current_account)
    set_locale(locale, &)
  end

  def locale_from_custom_domain
    return if params[:locale]

    domain = request.host
    return if DomainHelper.hub_domain?(domain)

    @portal = Portal.find_by(custom_domain: domain)
    return unless @portal

    LanguageConfig.enabled?(@portal.default_locale) ? @portal.default_locale : nil
  end

  def set_locale(locale, &)
    locale ||= I18n.default_locale
    I18n.with_locale(locale, &)
  end

  def locale_from_params
    LanguageConfig.enabled?(params[:locale]) ? params[:locale] : nil
  end

  def locale_from_account(account)
    return unless account

    LanguageConfig.enabled?(account.locale) ? account.locale : nil
  end

  def locale_from_env_variable
    return unless ENV.fetch('DEFAULT_LOCALE', nil)

    LanguageConfig.enabled?(ENV.fetch('DEFAULT_LOCALE')) ? ENV.fetch('DEFAULT_LOCALE') : nil
  end
end
