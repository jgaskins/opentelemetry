require "../proto/trace.pb"
require "../proto/common.pb"

# :nodoc:
class Fiber
  property current_otel_trace_id : Bytes?
  property current_otel_resource_spans : OpenTelemetry::Proto::Trace::V1::ResourceSpans?
  property current_otel_span : OpenTelemetry::Proto::Trace::V1::Span?

  def current_otel_resource_spans!
    self.current_otel_resource_spans ||= OpenTelemetry::Proto::Trace::V1::ResourceSpans.new(
      instrumentation_library_spans: [
        OpenTelemetry::Proto::Trace::V1::InstrumentationLibrarySpans.new(
          instrumentation_library: OpenTelemetry::Proto::Common::V1::InstrumentationLibrary.new(
            name: "OpenTelemetry Crystal",
            version: OpenTelemetry::VERSION,
          ),
          spans: [] of OpenTelemetry::Proto::Trace::V1::Span,
        ),
      ],
    )
  end
end
