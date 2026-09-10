class Enterprise::ClearbitLookupService
  CLEARBIT_ENDPOINT = 'https://person.clearbit.com/v2/combined/find'.freeze

  def self.lookup(email)
    return nil unless clearbit_enabled?

    response = perform_request(email)
    process_response(response)
  rescue StandardError => e
    Rails.logger.error "[ClearbitLookup] #{e.message}"
    nil
  end

  def self.perform_request(email)
    HTTParty.get(
      CLEARBIT_ENDPOINT,
      headers: { 'Authorization' => "Bearer #{clearbit_token}" },
      query: { email: email }
    )
  end

  def self.clearbit_enabled?
    clearbit_token.present?
  end

  def self.clearbit_token
    GlobalConfigService.load('CLEARBIT_API_KEY', '')
  end

  def self.process_response(response)
    return handle_error(response) unless response.success?

    format_response(response)
  end

  def self.handle_error(response)
    Rails.logger.error "[ClearbitLookup] API Error: #{response.message} (Status: #{response.code})"
    nil
  end

  def self.format_response(response)
    data = response.parsed_response
    {
      name: data.dig('person', 'name', 'fullName'),
      avatar: data.dig('person', 'avatar'),
      company_name: data.dig('company', 'name'),
      timezone: data.dig('company', 'timeZone'),
      logo: data.dig('company', 'logo'),
      industry: data.dig('company', 'category', 'industry'),
      company_size: data.dig('company', 'metrics', 'employees')
    }
  end
end
