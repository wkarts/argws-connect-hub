module Whatsapp::Groups
  module StorageGuard
    def show
      candidate = if defined?(@blob) && @blob
                    @blob
                  elsif params[:encoded_key].present?
                    decoded = ActiveStorage.verifier.verified(params[:encoded_key], purpose: :blob_key)
                    Whatsapp::Groups::StorageGuard.source_for_key(decoded[:key] || decoded['key']) if decoded.is_a?(Hash)
                  end
      return head :not_found if candidate && Whatsapp::Groups::StorageGuard.protected?(candidate)
      super
    end

    # Untracked variants do not have a Blob row of their own. This method is
    # called only after verification of the disk service's signed blob key.
    def self.source_for_key(key)
      return unless key.is_a?(String)
      direct = ActiveStorage::Blob.find_by(key: key)
      return direct if direct

      variant = key.match(%r{\Avariants/(.+)/[a-f0-9]{64}\z})
      ActiveStorage::Blob.find_by(key: variant[1]) if variant
    end

    def self.protected?(blob, ancestors = [])
      # Fail closed for a malformed cycle or excessive derivative ancestry.
      return true if ancestors.include?(blob.id) || ancestors.length >= 12
      return true if blob.attachments.where(record_type: 'WhatsappGroupMessage').exists?

      ids = blob.attachments.where(record_type: 'Attachment').select(:record_id)
      ticket_file = Attachment.where(id: ids).joins(message: { conversation: [:contact_inbox, :inbox] })
                              .where(inboxes: { channel_type: 'Channel::Whatsapp', channel_id: Channel::Whatsapp.where(provider: 'connectapi').select(:id) })
                              .where("contact_inboxes.source_id ~ ?", '^[0-9]+(-[0-9]+)?@g\\.us$').exists?
      return true if ticket_file

      # A tracked variant is attached to VariantRecord; a preview image is
      # attached to its original Blob. Protect their public URLs as well as
      # the original, without restricting unrelated avatars or public files.
      owners = blob.attachments.where(record_type: ['ActiveStorage::VariantRecord', 'ActiveStorage::Blob'])
      owners.any? do |attachment|
        owner = attachment.record
        source = attachment.record_type == 'ActiveStorage::VariantRecord' ? owner&.blob : owner
        source.nil? || protected?(source, ancestors + [blob.id])
      end
    end
  end
end
