module SuperAdmin::FeaturesHelper
  def self.available_features
    YAML.load(ERB.new(Rails.root.join('enterprise/app/helpers/super_admin/features.yml').read).result).with_indifferent_access
  end

  def self.plan_details
    "Esta instalação utiliza a edição <span class='font-semibold'>Enterprise</span>."
  end
end
