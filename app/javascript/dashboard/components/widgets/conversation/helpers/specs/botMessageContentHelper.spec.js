import { generateBotMessageContent } from '../botMessageContentHelper';

describe('#generateBotMessageContent', () => {
  it('return correct input_select content', () => {
    expect(
      generateBotMessageContent('input_select', {
        submitted_values: [{ value: 'salad', title: 'Salad' }],
      })
    ).toEqual('<strong>Salad</strong>');
  });

  it('return correct input_email content', () => {
    expect(
      generateBotMessageContent('input_email', {
        submitted_email: 'hello@hub.com',
      })
    ).toEqual('<strong>hello@hub.com</strong>');
  });

  it('return correct input_csat content', () => {
    expect(
      generateBotMessageContent('input_csat', {
        submitted_values: {
          csat_survey_response: {
            rating: 5,
            feedback_message: 'Great Service',
          },
        },
      })
    ).toEqual(
      '<div><strong>Rating</strong></div><p>😍</p><div><strong>Feedback</strong></div><p>Great Service</p>'
    );

    expect(
      generateBotMessageContent(
        'input_csat',
        {
          submitted_values: {
            csat_survey_response: { rating: 1, feedback_message: '' },
          },
        },
        { csat: { ratingTitle: 'റേറ്റിംഗ്', feedbackTitle: 'പ്രതികരണം' } }
      )
    ).toEqual('<div><strong>റേറ്റിംഗ്</strong></div><p>😞</p>');
  });

  it('return correct form content', () => {
    expect(
      generateBotMessageContent('form', {
        items: [
          {
            name: 'large_text',
            label: 'This a large text',
          },
          {
            name: 'email',
            label: 'Email',
          },
        ],
        submitted_values: [{ name: 'large_text', value: 'Large Text Content' }],
      })
    ).toEqual(
      '<div>This a large text</div><strong>Large Text Content</strong><br/><br/><div>Email</div><strong>No response</strong><br/><br/>'
    );
  });
});
