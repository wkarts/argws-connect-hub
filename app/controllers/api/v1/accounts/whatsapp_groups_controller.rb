class Api::V1::Accounts::WhatsappGroupsController < Api::V1::Accounts::BaseController
  before_action :require_person
  before_action :disable_caching
  before_action :load_group, except: [:index]

  def index
    scope = Whatsapp::Groups::Access.scope(Current.user, Current.account, active: true)
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    if params[:q].present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.first(120))}%"
      scope = scope.where('whatsapp_groups.name ILIKE ?', query)
    end
    page = [params[:page].to_i, 1].max
    render json: { groups: scope.order(Arel.sql('whatsapp_groups.last_activity_at DESC NULLS LAST, whatsapp_groups.id DESC'))
                               .offset((page - 1) * 25).limit(25).map { |group| Whatsapp::Groups::Presenter.group(group, Current.user) },
                   total: scope.count, page: page, per_page: 25 }
  end

  def show
    render json: Whatsapp::Groups::Presenter.group(@group, Current.user)
  end

  def legacy_messages
    conversations = @group.conversations.where(inbox_id: Current.user.assigned_inboxes.select(:id))
    scope = Message.where(conversation_id: conversations.select(:id)).includes(:sender, attachments: { file_attachment: :blob })
    scope = scope.where('messages.id < ?', params[:before].to_i) if params[:before].present?
    records = scope.reorder(id: :desc).limit(50).to_a
    render json: { messages: records.reverse.map { |message| Whatsapp::Groups::Presenter.legacy_message(message) },
                   next_before: records.size == 50 ? records.last.id : nil }
  end

  def preference
    values = params.require(:preference).permit(:muted, :read, :last_message_id).to_h
    if values.key?('muted') && ![true, false].include?(values['muted'])
      raise ActionController::BadRequest, 'muted must be boolean'
    end
    preference = @group.whatsapp_group_preferences.find_or_create_by!(user: Current.user)
    preference.with_lock do
      preference.muted = values['muted'] if values.key?('muted')
      if values['read'] == true
        last_seen = values['last_message_id'].present? ? @group.whatsapp_group_messages.find(values['last_message_id']).sent_at : Time.current
        preference.last_read_at = [preference.last_read_at || Time.at(0), last_seen].max
      end
      preference.save!
    end
    render json: Whatsapp::Groups::Presenter.group(@group, Current.user)
  end

  private

  def require_person
    raise Pundit::NotAuthorizedError unless Current.user.is_a?(User)
    Current.account_user = Current.account.account_users.find_by(user_id: Current.user.id)
    raise Pundit::NotAuthorizedError unless Current.account_user
  end

  def load_group
    @group = Whatsapp::Groups::Access.scope(Current.user, Current.account, active: true).find(params[:id])
  end

  def disable_caching
    response.headers['Cache-Control'] = 'private, no-store'
  end
end
