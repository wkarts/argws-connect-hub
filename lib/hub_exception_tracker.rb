# HUB exception handling writes only to the local Rails logger.
# Context metadata is accepted for compatibility with existing call sites,
# but nothing is transmitted to an external error tracking service.
class HubExceptionTracker
  def initialize(exception, context: nil, **metadata)
    @exception = exception
    @context = (context || {}).merge(metadata)
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
