require "db/pool"
require "http"

require "./ext/fiber"

require "./exporter"
require "./proto/trace.pb"
require "./proto/trace_service.pb"

# TODO: Write documentation for `OpenTelemetry`
module OpenTelemetry
  VERSION = "0.3.4"

  # The primary interface for OpenTelemetry tracing, called whenever you want to
  # either create a new trace or add nested spans to an existing trace.
  #
  # ```
  # def query(sql : String, args : Array)
  #   OpenTelemetry.trace "db.query" do |span|
  #     span["query.sql"] = sql
  #     span["query.args"] = args.to_s
  #     result = run_query(sql, args)
  #     span["query.result_count"] = result.size
  #
  #     result
  #   end
  # end
  # ```
  def self.trace(name : String)
    trace = current_trace
    is_new_trace = current_trace_id.nil?
    trace_id = self.current_trace_id ||= Random::Secure.random_bytes(16)
    previous_current_span = current_span
    span = API::Span.new(
      name: name,
      trace_id: trace_id,
      parent_id: previous_current_span.try(&.id),
      kind: :internal
    )
    self.current_span = span
    span["service.name"] = CONFIG.service_name

    span.started!
    trace.spans << span

    begin
      yield span
    rescue ex
      span.status = Proto::Trace::V1::Status.new(
        code: :error,
        message: "#{ex.class.name}: #{ex.message}",
      )
      raise ex
    ensure
      span.ended!
      Fiber.current.current_otel_span = previous_current_span

      if previous_current_span.nil?
        self.current_trace_id = nil if is_new_trace
        CONFIG.exporter.trace(trace.to_protobuf)
        reset_current_trace!
      end
    end
  end

  # :nodoc:
  def self.current_trace_id
    Fiber.current.current_otel_trace_id
  end

  # :nodoc:
  def self.current_trace_id=(value : Bytes?)
    Fiber.current.current_otel_trace_id = value
  end

  # :nodoc:
  def self.current_trace
    Fiber.current.current_otel_trace!
  end

  # :nodoc:
  def self.reset_current_trace!
    Fiber.current.current_otel_trace = nil
  end

  # :nodoc:
  def self.current_span
    Fiber.current.current_otel_span
  end

  # :nodoc:
  def self.current_span=(span : API::Span)
    Fiber.current.current_otel_span = span
  end

  # Global OpenTelemetry configuration, intended to be called when your
  # application starts. See `OpenTelemetry::Configuration` for more details.
  #
  # ```
  # OpenTelemetry.configure do |c|
  #   c.exporter = OpenTelemetry::HTTPExporter.new(
  #     # Send data to Honeycomb
  #     endpoint: URI.parse("https://api.honeycomb.io")
  #     headers: HTTP::Headers {
  #       "x-honeycomb-team"    => ENV["HONEYCOMB_API_KEY"],
  #       "x-honeycomb-dataset" => ENV["HONEYCOMB_DATASET"],
  #     }
  #   )
  # end
  # ```
  def self.configure
    yield CONFIG
  end

  # Configuration for OpenTelemetry, see `OpenTelemetry.configure` for usage.
  class Configuration
    # Set the `OpenTelemetry::Exporter` instance.
    property exporter : Exporter = NullExporter.new
    property service_name : String? = ""
  end

  # :nodoc:
  CONFIG = Configuration.new

  # An `HTTP::Handler` compatible with any `HTTP::Server`-based framework,
  # including [Lucky](https://luckyframework.org) and [Amber](https://amberframework.org).
  #
  # For plain `HTTP::Server`:
  #
  # ```
  # http = HTTP::Server.new([
  #   HTTP::LogHandler.new,
  #   OpenTelemetry::Middleware.new("top-level-span-name"),
  #   YourApp.new,
  # ])
  # ```
  class Middleware
    include HTTP::Handler

    def initialize(@name : String)
    end

    def call(context : HTTP::Server::Context)
      OpenTelemetry.trace @name do |span|
        span.kind = :server
        span["request.path"] = context.request.path
        span["request.method"] = context.request.method
        context.request.query_params.each do |key, value|
          span["request.query_params.#{key}"] = value
        end

        begin
          call_next context
        ensure
          span["response.status_code"] = context.response.status_code.to_i64
          if context.response.status_code < 400
            span.status = Proto::Trace::V1::Status.new(code: :ok)
          end
          # pp current_trace: OpenTelemetry.current_trace
        end
      end
    end
  end

  module API
    class Trace
      getter id : Bytes = Random::Secure.random_bytes(16)
      getter spans = [] of Span

      def to_protobuf
        Proto::Trace::V1::ResourceSpans.new(
          instrumentation_library_spans: [
            Proto::Trace::V1::InstrumentationLibrarySpans.new(
              spans: spans.map(&.to_protobuf)
            ),
          ],
        )
      end
    end

    class Span
      alias PrimitiveAttributeValue = String | Int32 | Int64 | Bool | Nil
      alias AttributeValue = PrimitiveAttributeValue | Hash(String, PrimitiveAttributeValue) | Array(PrimitiveAttributeValue)

      getter name : String
      getter id : Bytes = Random::Secure.random_bytes(8)
      getter trace_id : Bytes
      getter parent_id : Bytes?
      getter attributes = {} of String => AttributeValue
      getter started_at : Time?
      getter ended_at : Time?
      property kind : Proto::Trace::V1::Span::SpanKind
      property status : Proto::Trace::V1::Status?

      def initialize(@name, @trace_id, @parent_id, @kind : Proto::Trace::V1::Span::SpanKind)
      end

      def []=(key : String, value : AttributeValue)
        attributes[key] = value
      end

      def []?(key : String)
        attributes[key]?
      end

      def started!(now : Time = Time.utc)
        @started_at = now
      end

      def ended!(now : Time = Time.utc)
        @ended_at = now
      end

      def to_protobuf
        span = Proto::Trace::V1::Span.new(
          name: name,
          span_id: id,
          trace_id: trace_id,
          parent_span_id: parent_id,
          start_time_unix_nano: started_at_nanoseconds,
          end_time_unix_nano: ended_at_nanoseconds,
          kind: kind,
        )

        attributes.each do |key, value|
          span[key] = value
        end

        span
      end

      private def started_at_nanoseconds
        if started_at = self.started_at
          (started_at - Time::UNIX_EPOCH).total_nanoseconds.to_u64
        end
      end

      private def ended_at_nanoseconds
        if ended_at = self.ended_at
          (ended_at - Time::UNIX_EPOCH).total_nanoseconds.to_u64
        end
      end
    end
  end
end

module OpenTelemetry
  module Proto
    module Trace
      module V1
        struct Span
          # Shorthand for adding an attribute to a span
          def []=(key : String, value)
            attributes = @attributes ||= [] of Common::V1::KeyValue
            if kv = attributes.find { |kv| kv.key == key }
              kv.value = Common::V1::AnyValue.new(value)
            else
              attributes << Common::V1::KeyValue.new(
                key: key,
                value: Common::V1::AnyValue.new(value),
              )
            end
            value
          end

          def [](key : String)
            if attributes = self.attributes
              attributes.each do |kv|
                return kv.unwrapped_value if kv.key == key
              end

              missing_attribute! key
            else
              missing_attribute! key
            end
          end

          def []?(key : String)
            if attributes = self.attributes
              attributes.each do |kv|
                return kv.unwrapped_value if kv.key == key
              end
            end

            nil
          end

          def missing_attribute!(key : String)
            raise KeyError.new("No attribute #{key.inspect} for span #{name.inspect}")
          end
        end
      end
    end

    module Common
      module V1
        struct AnyValue
          def initialize(@string_value : String)
          end

          def initialize(@bool_value : Bool)
          end

          def initialize(int_value : Int)
            @int_value = int_value.to_i64
          end

          def initialize(double_value : Float)
            @double_value = double_value.to_f64
          end

          def initialize(array_value : Array)
            @array_value = ArrayValue.new(array_value.map { |value|
              AnyValue.new(value)
            })
          end

          def initialize(kvlist_value : Hash)
            values = Array(KeyValue).new(initial_capacity: kvlist_value.size)
            kvlist_value.each do |key, value|
              values << KeyValue.new(key: key, value: AnyValue.new(value))
            end

            @kvlist_value = KeyValueList.new(values)
          end

          def initialize(@bytes_value : Bytes)
          end

          def initialize(nil_value : Nil)
          end

          def unwrapped_value
            string_value || bool_value || int_value || double_value || array_value || kvlist_value || bytes_value
          end
        end

        struct KeyValue
          def unwrapped_value
            if value = self.value
              value.unwrapped_value
            end
          end
        end
      end
    end
  end
end
