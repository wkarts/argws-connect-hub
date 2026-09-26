module Whatsapp::Groups
  class MediaSession
    COOKIE = :hub_group_media_session
    PATH = '/api/v1/group_files'.freeze

    # A narrowly scoped, encrypted HttpOnly cookie allows native img/audio/video
    # elements to load protected files. It is not accepted by other API routes.
    # It refers to the existing Devise device session, not another HUB login.
    def self.issue(controller)
      user = controller.send(:current_user)
      client = controller.request.headers['client'].to_s
      return unless user.is_a?(User) && client.present?
      session = user.tokens.to_h[client].to_h
      expiry = [session['expiry'].to_i, 30.minutes.from_now.to_i].min
      return unless expiry > Time.current.to_i
      existing = controller.cookies.encrypted[COOKIE]
      if existing.is_a?(Hash)
        saved = existing.with_indifferent_access
        return if saved[:user_id] == user.id && saved[:client] == client && saved[:expiry].to_i > 5.minutes.from_now.to_i
      end
      controller.cookies.encrypted[COOKIE] = {
        value: { user_id: user.id, client: client, expiry: expiry },
        httponly: true, secure: controller.request.ssl?, same_site: :strict,
        path: PATH, expires: Time.at(expiry)
      }
    end

    def self.reader(cookies)
      value = cookies.encrypted[COOKIE]
      return unless value.is_a?(Hash)
      data = value.with_indifferent_access
      return unless data[:expiry].to_i > Time.current.to_i
      user = User.find_by(id: data[:user_id])
      return unless user&.active_for_authentication?
      session = user.tokens.to_h[data[:client].to_s].to_h
      return unless session['expiry'].to_i > Time.current.to_i
      user
    end
  end
end
