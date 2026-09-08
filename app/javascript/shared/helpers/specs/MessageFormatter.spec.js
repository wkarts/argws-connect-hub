import MessageFormatter from '../MessageFormatter';

describe('#MessageFormatter', () => {
  describe('content with links', () => {
    it('should format correctly', () => {
      const message =
        'Hub is an opensource tool. [Hub](https://www.hub.com)';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        '<p>Hub is an opensource tool. <a href="https://www.hub.com" class="link" rel="noreferrer noopener nofollow" target="_blank">Hub</a></p>'
      );
    });
    it('should format correctly', () => {
      const message =
        'Hub is an opensource tool. https://www.hub.com';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        '<p>Hub is an opensource tool. <a href="https://www.hub.com" class="link" rel="noreferrer noopener nofollow" target="_blank">https://www.hub.com</a></p>'
      );
    });
  });

  describe('parses heading to strong', () => {
    it('should format correctly', () => {
      const message = '### opensource \n ## tool';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        `<h3>opensource</h3>
<h2>tool</h2>`
      );
    });
  });

  describe('content with image and has "cw_image_height" query at the end of URL', () => {
    it('should set image height correctly', () => {
      const message =
        'Hub is an opensource tool. ![](http://hub.com/hub.png?cw_image_height=24px)';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        '<p>Hub is an opensource tool. <img src="http://hub.com/hub.png?cw_image_height=24px" alt="" style="height: 24px;" /></p>'
      );
    });

    it('should set image height correctly if its original size', () => {
      const message =
        'Hub is an opensource tool. ![](http://hub.com/hub.png?cw_image_height=auto)';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        '<p>Hub is an opensource tool. <img src="http://hub.com/hub.png?cw_image_height=auto" alt="" style="height: auto;" /></p>'
      );
    });

    it('should not set height', () => {
      const message =
        'Hub is an opensource tool. ![](http://hub.com/hub.png)';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        '<p>Hub is an opensource tool. <img src="http://hub.com/hub.png" alt="" /></p>'
      );
    });
  });

  describe('tweets', () => {
    it('should return the same string if not tags or @mentions', () => {
      const message = 'Hub is an opensource tool';
      expect(new MessageFormatter(message).formattedMessage).toMatch(message);
    });

    it('should add links to @mentions', () => {
      const message =
        '@hubapp is an opensource tool thanks @longnonexistenttwitterusername';
      expect(
        new MessageFormatter(message, true, false).formattedMessage
      ).toMatch(
        '<p><a href="http://twitter.com/hubapp" class="link" rel="noreferrer noopener nofollow" target="_blank">@hubapp</a> is an opensource tool thanks @longnonexistenttwitterusername</p>'
      );
    });

    it('should add links to #tags', () => {
      const message = '#hubapp is an opensource tool';
      expect(
        new MessageFormatter(message, true, false).formattedMessage
      ).toMatch(
        '<p><a href="https://twitter.com/hashtag/hubapp" class="link" rel="noreferrer noopener nofollow" target="_blank">#hubapp</a> is an opensource tool</p>'
      );
    });
  });

  describe('private notes', () => {
    it('should return the same string if not tags or @mentions', () => {
      const message = 'Hub is an opensource tool';
      expect(new MessageFormatter(message).formattedMessage).toMatch(message);
    });

    it('should add links to @mentions', () => {
      const message =
        '@hubapp is an opensource tool thanks @longnonexistenttwitterusername';
      expect(
        new MessageFormatter(message, false, true).formattedMessage
      ).toMatch(message);
    });

    it('should add links to #tags', () => {
      const message = '#hubapp is an opensource tool';
      expect(
        new MessageFormatter(message, false, true).formattedMessage
      ).toMatch(message);
    });
  });

  describe('plain text content', () => {
    it('returns the plain text without HTML', () => {
      const message =
        '<b>Hub is an opensource tool. https://www.hub.com</b>';
      expect(new MessageFormatter(message).plainText).toMatch(
        'Hub is an opensource tool. https://www.hub.com'
      );
    });
  });

  describe('#sanitize', () => {
    it('sanitizes markup and removes all unnecessary elements', () => {
      const message =
        '[xssLink](javascript:alert(document.cookie))\n[normalLink](https://google.com)**I am a bold text paragraph**';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        `<p>[xssLink](javascript:alert(document.cookie))<br />
<a href="https://google.com" class="link" rel="noreferrer noopener nofollow" target="_blank">normalLink</a><strong>I am a bold text paragraph</strong></p>`
      );
    });
  });
});
