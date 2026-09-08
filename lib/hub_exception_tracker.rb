# HUB intentionally keeps exception handling local.
# External exception/telemetry collectors are not used.
class HubExceptionTracker
  def initialize(exception, context: {})
    @exception = exception
    @context = context
  end

  def capture_exception
    Rails.logger.error({
      error_class: @exception.class.name,
      message: @exception.message,
      context: @context,
      backtrace: Array(@exception.backtrace).first(20)
    })
  rescue StandardError
    nil
  end
end
