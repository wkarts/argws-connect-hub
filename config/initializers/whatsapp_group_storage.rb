Rails.application.config.to_prepare do
  [ActiveStorage::Blobs::RedirectController, ActiveStorage::Blobs::ProxyController,
   ActiveStorage::Representations::RedirectController, ActiveStorage::Representations::ProxyController,
   ActiveStorage::DiskController].each do |controller|
    controller.prepend(Whatsapp::Groups::StorageGuard) unless controller < Whatsapp::Groups::StorageGuard
  end
end
