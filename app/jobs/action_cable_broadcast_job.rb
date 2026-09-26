class ActionCableBroadcastJob < ApplicationJob
  queue_as :critical

  def perform(members, event_name, data)
    Whatsapp::Groups::BroadcastFilter.for(members, event_name, data).each do |member, authorized_data|
      ActionCable.server.broadcast(member, { event: event_name, data: authorized_data })
    end
  end
end
