require "./proto/trace.pb"
require "mpsc"
require "log"

module OpenTelemetry
  # The `Exporter` is what sends your telemetry data out for processing,
  # analysis, aggregation, etc.
  module Exporter
    alias Trace = Proto::Trace::V1::ResourceSpans

    abstract def trace(traces : Array(Trace))

    # Send a single trace to the exporter's trace endpoint
    def trace(trace : Trace)
      trace [trace]
    end
  end

  # A `BatchExporter` reports data in batches when either a time or trace-count
  # threshold has been reached. By default, it will report at least once per
  # second in batches of up to 100.
  class BatchExporter
    include Exporter

    alias Buffer = MPSC::Channel(Trace)

    # The maximum amount of time to hold onto data before forwarding it to other
    # exporters.
    getter duration : Time::Span

    # The maximum buffer size, for example 100 traces
    getter max_size : Int32

    @buffer = Buffer.new
    @log = Log.for(BatchExporter)

    # Constructor that receives a single exporter
    def self.new(exporter : Exporter, duration = 1.second, max_size = 100, log = Log.for(self))
      new([exporter.as(Exporter)], duration, max_size, log)
    end

    # Receives a list of exporters to delegate to
    def initialize(@exporters : Array(Exporter), @duration : Time::Span = 1.second, @max_size = 100, @log = Log.for(self))
    end

    # Add the given traces to the buffer
    def trace(traces : Array(Trace))
      @log.trace { "Received #{traces.size} traces" }
      traces.each do |trace|
        @buffer.send trace
      end
    end

    def start
      traces = [] of Trace
      start = Time.monotonic
      loop do
        while traces.size < @max_size && (trace = @buffer.receive?)
          traces << trace
        end

        # If we've reached a threshold, we need to send any traces we have
        if Time.monotonic - start >= @duration || traces.size >= @max_size
          if traces.any?
            @log.debug do |emitter|
              total_spans = traces.flat_map { |t| (t.instrumentation_library_spans || [] of Proto::Trace::V1::InstrumentationLibrarySpans).flat_map(&.spans) }.size
              emitter.emit "Sending #{traces.size} traces", total_spans: total_spans
            end
            @exporters.each(&.trace(traces))
          end

          # Clear out the buffer for the next batch
          traces.clear

          # Restart the clock
          start = Time.monotonic
        end

        # Give other fibers time to populate the buffer
        sleep 100.milliseconds
      end
    end
  end

  # The `HTTPExporter` sends your telemetry data to an HTTP service using
  # [OTLP/HTTP](https://github.com/open-telemetry/opentelemetry-specification/blob/32fcc01a6b2051fff84eea41eb1e79b42277e269/specification/protocol/otlp.md#otlphttp).
  class HTTPExporter
    include Exporter

    getter endpoint : URI
    getter headers : HTTP::Headers
    @pool : DB::Pool(HTTP::Client)
    @channel = Channel(Array(Trace)).new(100)
    @log = Log.for(HTTPExporter)

    # Configures the exporter to send telemetry to the given HTTP collector for
    # OpenTelemetry data.
    def initialize(@endpoint : URI, @headers : HTTP::Headers)
      pool_options = {
        max_idle_pool_size: ENV.fetch("OTEL_HTTP_EXPORTER_MAX_POOL_IDLE_SIZE", "6").to_i,
        max_pool_size: ENV.fetch("OTEL_HTTP_EXPORTER_MAX_POOL_SIZE", "6").to_i,
      }

      @pool = DB::Pool.new(**pool_options) do
        http = HTTP::Client.new(@endpoint)
        http.before_request do |request|
          h = request.headers
          @headers.each do |key, value|
            h[key] = value
          end
          h["content-type"] = "application/protobuf"
          h["connection"] = "keep-alive"
        end
        http
      end

      spawn do
        loop do
          traces = @channel.receive

          @pool.checkout do |http|
            @log.debug { "Sending #{traces.size} traces" }
            http.post "/v1/traces", body: Proto::Collector::Trace::V1::ExportTraceServiceRequest.new(resource_spans: traces).to_protobuf.to_slice
          end
        end
      end
    end

    # Send a collection of traces to the exporters trace endpoint
    def trace(traces : Array(Trace))
      @log.trace { "Received #{traces.size} traces" }
      @channel.send traces
    end
  end

  class NullExporter
    include Exporter

    def trace(traces : Array(Trace))
    end
  end
end
