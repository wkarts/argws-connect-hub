class Notification::PushNotificationJob < ApplicationJob
  queue_as :default

  def perform(notification)
    return unless Whatsapp::Groups::Access.notification_allowed?(notification)
    Notification::PushNotificationService.new(notification: notification).perform
  end
end
