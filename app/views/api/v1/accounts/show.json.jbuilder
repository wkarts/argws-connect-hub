json.partial! 'api/v1/models/account', formats: [:json], resource: @account
json.latest_hub_version @latest_hub_version
json.partial! 'enterprise/api/v1/accounts/partials/account', account: @account if HubApp.enterprise?
