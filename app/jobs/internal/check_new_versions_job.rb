class Internal::CheckNewVersionsJob < ApplicationJob
  queue_as :low
  def perform; nil; end
end
