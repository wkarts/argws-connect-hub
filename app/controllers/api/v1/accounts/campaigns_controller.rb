class Api::V1::Accounts::CampaignsController < Api::V1::Accounts::BaseController
  before_action :campaign, except: [:index, :create]
  before_action :check_authorization

  def index
    @campaigns = Current.account.campaigns
  end

  def show; end

  def create
    @campaign = Current.account.campaigns.new(campaign_attributes)
    replace_materials!(@campaign) if materials_supplied?
    @campaign.save!
  end

  def update
    @campaign.assign_attributes(campaign_attributes)
    replace_materials!(@campaign) if materials_supplied?
    @campaign.save!
  end

  def destroy
    @campaign.destroy!
    head :ok
  end

  private

  def campaign
    @campaign ||= Current.account.campaigns.find_by(display_id: params[:id])
  end

  def campaign_attributes
    campaign_params.except(:material_blob_ids)
  end

  def materials_supplied?
    params.require(:campaign).key?(:material_blob_ids)
  end

  def replace_materials!(campaign_record)
    blobs = Array(campaign_params[:material_blob_ids]).filter_map do |signed_id|
      ActiveStorage::Blob.find_signed(signed_id)
    end

    requested_count = Array(campaign_params[:material_blob_ids]).reject(&:blank?).size
    if blobs.size != requested_count
      campaign_record.errors.add(:materials, 'contains an invalid upload reference')
      raise ActiveRecord::RecordInvalid, campaign_record
    end

    campaign_record.materials = blobs
  end

  def campaign_params
    params.require(:campaign).permit(
      :title,
      :description,
      :message,
      :enabled,
      :campaign_type,
      :trigger_only_during_business_hours,
      :inbox_id,
      :sender_id,
      :scheduled_at,
      audience: [:type, :id],
      trigger_rules: {},
      message_attributes: {},
      material_blob_ids: []
    )
  end
end
