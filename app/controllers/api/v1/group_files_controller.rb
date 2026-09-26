class Api::V1::GroupFilesController < ApplicationController
  include AccessTokenAuthHelper
  before_action :authorize_file

  def show
    blob = @file.blob
    thumbnail = params[:thumb] == '1' && blob.variable?
    variant = blob.variant(resize_to_limit: [320, 320]).processed if thumbnail
    data = variant.download if thumbnail
    total = thumbnail ? data.bytesize : blob.byte_size
    response.headers['Cache-Control'] = 'private, no-store, max-age=0'
    response.headers['Pragma'] = 'no-cache'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Content-Security-Policy'] = "default-src 'none'; sandbox"
    response.headers['Referrer-Policy'] = 'no-referrer'
    response.headers['Accept-Ranges'] = 'bytes'
    mime = thumbnail ? variant.variation.content_type : blob.content_type.to_s
    filename = thumbnail ? variant.filename.to_s : blob.filename.to_s
    inline = mime.match?(%r{\A(image/(png|jpeg|gif|webp)|audio/[a-z0-9.+-]+|video/[a-z0-9.+-]+)\z})
    status = :ok
    if request.headers['Range'].present?
      range = request.headers['Range'].match(/\Abytes=(\d*)-(\d*)\z/)
      return invalid_range(total) unless range && (range[1].present? || range[2].present?)
      first = range[1].present? ? range[1].to_i : [total - range[2].to_i, 0].max
      last = range[1].blank? || range[2].blank? ? total - 1 : [range[2].to_i, total - 1].min
      return invalid_range(total) unless first >= 0 && first <= last && first < total
      data = thumbnail ? data.byteslice(first..last) : blob.download_chunk(first..last)
      response.headers['Content-Range'] = "bytes #{first}-#{last}/#{total}"
      status = :partial_content
    else
      data ||= blob.download
    end
    response.headers['Content-Length'] = data.bytesize.to_s
    send_data data, filename: filename, type: mime.presence || 'application/octet-stream',
                    disposition: inline ? 'inline' : 'attachment', status: status
  end

  private

  def authorize_file
    if request.headers['api_access_token'].present?
      authenticate_access_token!
      return if performed?
      @reader = @resource if @resource.is_a?(User)
    else
      @reader = current_user || Whatsapp::Groups::MediaSession.reader(cookies)
    end
    raise Pundit::NotAuthorizedError unless @reader.is_a?(User)
    account = @reader.accounts.where(status: :active).find(params[:account_id])
    Current.user = @reader
    Current.account = account
    Current.account_user = account.account_users.find_by!(user_id: @reader.id)
    @group = Whatsapp::Groups::Access.scope(@reader, account).find(params[:group_id])
    if params[:domain] == 'management'
      message = @group.whatsapp_group_messages.find(params[:message_id])
      raise ActiveRecord::RecordNotFound if message.deleted_at
      @file = message.files.find(params[:attachment_id])
    elsif params[:domain] == 'conversation'
      conversation = @group.conversations.where(inbox_id: @reader.assigned_inboxes.where(account_id: account.id).select(:id))
                           .joins(:messages).where(messages: { id: params[:message_id] }).first!
      message = conversation.messages.find(params[:message_id])
      raise ActiveRecord::RecordNotFound if message.content_attributes.to_h['deleted']
      attachment = message.attachments.find(params[:attachment_id])
      raise ActiveRecord::RecordNotFound unless attachment.file.attached?
      @file = attachment.file
    else
      raise ActiveRecord::RecordNotFound
    end
  end

  def invalid_range(total)
    response.headers['Content-Range'] = "bytes */#{total}"
    head :range_not_satisfiable
  end
end
