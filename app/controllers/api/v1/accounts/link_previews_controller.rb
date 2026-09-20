# frozen_string_literal: true

class Api::V1::Accounts::LinkPreviewsController < Api::V1::Accounts::BaseController
  def show
    preview = LinkPreviews::Fetcher.new(params[:url]).perform
    render json: {
      preview: preview,
      preview_token: LinkPreviews::Token.issue(preview)
    }
  rescue LinkPreviews::Fetcher::Error => error
    Rails.logger.debug("[HUB link preview] #{error.message}")
    render json: { preview: nil }, status: :ok
  end
end
