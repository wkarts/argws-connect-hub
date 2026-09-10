class SuperAdmin::AccountsController < SuperAdmin::ApplicationController
  def resource_params
    permitted_params = super
    permitted_params[:limits] = permitted_params[:limits].to_h.compact
    permitted_params[:selected_feature_flags] = params[:enabled_features].keys.map(&:to_sym) if params[:enabled_features].present?
    permitted_params
  end

  def seed
    Internal::SeedAccountJob.perform_later(requested_resource)
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Geração de dados de demonstração iniciada.')
  end

  def reset_cache
    requested_resource.reset_cache_keys
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Chaves de cache removidas.')
  end

  def destroy
    account = Account.find(params[:id])
    DeleteObjectJob.perform_later(account) if account.present?
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'A exclusão da conta está em andamento.')
  end
end
