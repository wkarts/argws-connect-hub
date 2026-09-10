class ResponseBot::ResponseDocumentContentJob < ApplicationJob
  queue_as :default

  def perform(response_document)
    content = PageCrawlerService.new(response_document.document_link).body_text_content
    response_document.update!(content: content[0..15_000])
  end
end
