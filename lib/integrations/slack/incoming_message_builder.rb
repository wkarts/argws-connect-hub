class Integrations::Slack::IncomingMessageBuilder
  include Integrations::Slack::SlackMessageHelper

  attr_reader :params

  SUPPORTED_EVENT_TYPES = %w[event_callback url_verification].freeze
  SUPPORTED_EVENTS = %w[message link_shared].freeze
  SUPPORTED_MESSAGE_TYPES = %w[rich_text].freeze

  def initialize(params)
    @params = params
  end

  def perform
    return unless valid_event?

    if hook_verification?
      verify_hook
    elsif process_message_payload?
      process_message_payload
    elsif link_shared?
      SlackUnfurlJob.perform_later(params)
    end
  end

  private

  def valid_event?
    supported_event_type? && supported_event? && should_process_event?
  end

  def supported_event_type?
    SUPPORTED_EVENT_TYPES.include?(params[:type])
  end

  # Discard all the subtype of a message event
  # We are only considering the actual message sent by a Slack user
  # Any reactions or messages sent by the bot will be ignored.
  # https://api.slack.com/events/message#subtypes
  def should_process_event?
    return true if params[:type] != 'event_callback'

    params[:event][:user].present? && valid_event_subtype?
  end

  def valid_event_subtype?
    params[:event][:subtype].blank? || params[:event][:subtype] == 'file_share'
  end

  def supported_event?
    hook_verification? || SUPPORTED_EVENTS.include?(params[:event][:type])
  end

  def supported_message?
    if message.present?
      SUPPORTED_MESSAGE_TYPES.include?(message[:type]) && !attached_file_message?
    else
      params[:event][:files].present? && !attached_file_message?
    end
  end

  def hook_verification?
    params[:type] == 'url_verification'
  end

  def thread_timestamp_available?
    params[:event][:thread_ts].present?
  end

  def process_message_payload?
    thread_timestamp_available? && supported_message? && integration_hook
  end

  def link_shared?
    params[:event][:type] == 'link_shared'
  end

  def message
    params[:event][:blocks]&.first
  end

  def verify_hook
    {
      challenge: params[:challenge]
    }
  end

  def integration_hook
    @integration_hook ||= Integrations::Hook.find_by(reference_id: params[:event][:channel])
  end

  def slack_client
    @slack_client ||= Slack::Web::Client.new(token: @integration_hook.access_token)
  end

  # Keep Slack's synthetic 'Attached File!' text out of the HUB dashboard.
  # Postback messages that include event[:files] are handled as file messages.
  # As now we consider the postback message with event[:files]
  def attached_file_message?
    params[:event][:text] == 'Attached File!'
  end
end
