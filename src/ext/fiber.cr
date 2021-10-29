require "../proto/trace.pb"
require "../proto/common.pb"
require "../api"

# :nodoc:
class Fiber
  property current_otel_trace_id : Bytes?
  property current_otel_trace : OpenTelemetry::API::Trace?
  property current_otel_span : OpenTelemetry::API::Span?

  def current_otel_trace!
    self.current_otel_trace ||= OpenTelemetry::API::Trace.new
  end
end
