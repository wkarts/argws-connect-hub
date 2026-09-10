class SuperAdmin::EnterpriseBaseController < SuperAdmin::ApplicationController
  before_action :prepend_view_paths

  def prepend_view_paths
    prepend_view_path 'enterprise/app/views/'
  end
end
