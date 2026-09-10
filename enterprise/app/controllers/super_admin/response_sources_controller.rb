class SuperAdmin::ResponseSourcesController < SuperAdmin::EnterpriseBaseController
  before_action :set_response_source, only: %i[chat process_chat]

  def chat; end

  def process_chat
    previous_messages = []
    get_previous_messages(previous_messages)
    robin_response = ChatGpt.new(
      Enterprise::MessageTemplates::ResponseBotService.response_sections(params[:message], @response_source)
    ).generate_response(params[:message], previous_messages)

    message_content = robin_response['response']
    if robin_response['context_ids'].present?
      message_content += Enterprise::MessageTemplates::ResponseBotService.generate_sources_section(robin_response['context_ids'])
    end
    render json: { message: message_content }
  end

  private

  def get_previous_messages(previous_messages)
    Array(params[:previous_messages]).each do |message|
      role = message['type'] == 'user' ? 'user' : 'system'
      previous_messages << { content: message['message'], role: role }
    end
  end

  def set_response_source
    @response_source = requested_resource
  end
end
