class Features::BaseService
  MIGRATION_VERSION = ActiveRecord::Migration[7.0]

  def vector_extension_enabled?
    # Asset compilation happens while the application image is being built,
    # before PostgreSQL exists. Runtime processes do not set this flag and keep
    # the existing database-backed feature detection unchanged.
    return false if ENV['HUB_ASSETS_PRECOMPILE'] == '1'

    ActiveRecord::Base.connection.extension_enabled?('vector')
  end
end
