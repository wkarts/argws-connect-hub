module Liquidable
  extend ActiveSupport::Concern

  included do
    before_create :process_liquid_in_content
    before_create :process_liquid_in_template_params
  end

  private

  def message_drops
    {
      'contact' => ContactDrop.new(conversation.contact),
      'agent' => UserDrop.new(sender),
      'conversation' => ConversationDrop.new(conversation),
      'inbox' => InboxDrop.new(inbox),
      'account' => AccountDrop.new(conversation.account)
    }
  end

  def liquid_processable_message?
    content.present? && (message_type == 'outgoing' || message_type == 'template')
  end

  def process_liquid_in_content
    return unless liquid_processable_message?

    template = Liquid::Template.parse(modified_liquid_content)
    self.content = template.render(message_drops)
  rescue Liquid::Error
    # If there is an error in the liquid syntax, we don't want to process it
  end

  # WhatsApp template parameters travel separately from message.content.
  # Resolve the same HUB Liquid variables in both places before persistence so
  # Connect|API receives positional parameters already rendered by HUB.
  def process_liquid_in_template_params
    return unless liquid_processable_message?

    attributes = additional_attributes.to_h.deep_dup
    template_params = attributes['template_params']
    return unless template_params.is_a?(Hash)

    processed_params = template_params['processed_params']
    return unless processed_params.is_a?(Hash)

    template_params['processed_params'] = processed_params.transform_values do |value|
      next value unless value.is_a?(String)

      Liquid::Template.parse(value).render(message_drops)
    end
    self.additional_attributes = attributes
  rescue Liquid::Error
    # Keep the existing HUB behavior for invalid Liquid: do not transform it.
  end

  def modified_liquid_content
    # This regex is used to match the code blocks in the content
    # We don't want to process liquid in code blocks
    content.gsub(/`(.*?)`/m, '{% raw %}`\\1`{% endraw %}')
  end
end
