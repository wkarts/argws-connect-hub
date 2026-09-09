# frozen_string_literal: true

module Hub
  class HtmlToText
    BLOCK_TAGS = %w[address article aside blockquote div dl fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 header hr li main nav ol p pre section table tr ul].freeze

    def self.convert(html)
      new(html).convert
    end

    def initialize(html)
      @html = html.to_s
    end

    def convert
      fragment = Nokogiri::HTML.fragment(@html)
      fragment.css('script,style,noscript,template').remove

      fragment.css('br').each { |node| node.replace("\n") }
      fragment.css('li').each do |node|
        node.children.first.add_previous_sibling('- ') if node.children.first
      end
      fragment.css(BLOCK_TAGS.join(',')).each do |node|
        node.add_previous_sibling("\n")
        node.add_next_sibling("\n")
      end

      text = fragment.text
      text = text.gsub(/\r\n?/, "\n")
      text = text.gsub(/[\t\f\v ]+/, ' ')
      text = text.gsub(/ *\n */, "\n")
      text = text.gsub(/\n{3,}/, "\n\n")
      text.strip
    end
  end
end
